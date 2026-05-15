import Foundation
import os.log
import UIKit

/// Routes inbound kind:1 peer messages from the Rust core through the
/// access-control layer, queuing unknown senders for user approval and
/// dispatching allowed senders to `NostrAgentResponder`.
///
/// History note: this used to own a `URLSessionWebSocketTask`, a NIP-42 AUTH
/// dance, dedup gates, the since-cursor, and the kind:0 profile publisher.
/// All of that wire-protocol machinery now lives in the Rust core
/// (`PodcastrCore`). What stays in Swift is the bits that depend on
/// `AppStateStore` and `AgentAskCoordinator`: the dedup state
/// (`nostrBlockedPubkeys` / `nostrAllowedPubkeys` / `nostrPendingApprovals`),
/// the responder routing, and the lifecycle hooks. The body is intentionally
/// thin — the heavy lifting is in `PodcastrCoreBridge` and the Rust core.
@MainActor
final class NostrRelayService {
    nonisolated private static let logger = Logger.app("NostrRelayService")
    private let store: AppStateStore
    /// Owner-consultation surface from AppMain. Injected at init so the
    /// responder has it before `RootView.onAppear` fires — closes the
    /// cold-launch race where an inbound landing in the first few
    /// seconds would otherwise see `askCoordinator == nil` and have the
    /// `ask` tool short-circuit to an error envelope.
    private weak var askCoordinator: AgentAskCoordinator?
    /// Identifier returned by `core.subscribePeerMessages` — pass back to
    /// `core.unsubscribePeerMessages` on teardown.
    private var peerSubscriptionID: String?
    /// Multiplexed Swift-side handle. Pair with `peerSubscriptionID`: both
    /// must be torn down on `stop()` to free the registry slot AND release
    /// the relay-side subscription.
    private var peerHandle: PodcastrCoreBridge.SubscriptionHandle?
    /// Cached relay URL of the live subscription. Lets `start()` short-circuit
    /// when called with no settings changes (e.g. on every scene phase flip).
    private var connectedRelayURL: String?
    private lazy var profileFetcher = NostrProfileFetcher(store: store)
    /// Owns the inbound → LLM → outbound pipeline for allowed pubkeys.
    /// Kept lazy so apps with Nostr disabled never instantiate it.
    /// Exposed (read-only) so `RootView` can late-bind the podcast tool
    /// deps once the UI mounts. `askCoordinator` is plumbed here at
    /// init time and applied below.
    lazy var agentResponder: NostrAgentResponder = {
        let responder = NostrAgentResponder(store: store)
        responder.askCoordinator = askCoordinator
        return responder
    }()
    /// Tracks pubkeys we've already queued a profile fetch for during this
    /// session so a burst of inbound events from the same peer doesn't
    /// spam the relay with kind:0 requests. Cleared on `stop()`.
    private var profileFetchInflight: Set<String> = []

    /// Creates a new service backed by the given state store.
    /// `askCoordinator` is wired through to the lazy `agentResponder` on
    /// first access so peer-initiated `ask` tool calls can pop the
    /// owner-consent sheet from cold-launch onward.
    init(store: AppStateStore, askCoordinator: AgentAskCoordinator? = nil) {
        self.store = store
        self.askCoordinator = askCoordinator
    }

    // MARK: - Lifecycle

    /// Reads the current Nostr settings and opens a peer-message subscription
    /// on the Rust core, or stops the service if Nostr is disabled or
    /// misconfigured.
    func start() {
        let settings = store.state.settings
        guard settings.nostrEnabled,
              let pubkeyHex = settings.nostrPublicKeyHex, !pubkeyHex.isEmpty,
              !settings.nostrRelayURL.isEmpty else {
            NostrRelayService.logger.notice(
                "start: skipping — enabled=\(settings.nostrEnabled, privacy: .public), hasPubkey=\(settings.nostrPublicKeyHex?.isEmpty == false, privacy: .public), relayURL='\(settings.nostrRelayURL, privacy: .public)'"
            )
            stop()
            return
        }
        guard connectedRelayURL != settings.nostrRelayURL || peerSubscriptionID == nil else {
            NostrRelayService.logger.debug("start: already subscribed on \(settings.nostrRelayURL, privacy: .public); no-op")
            return
        }
        NostrRelayService.logger.notice(
            "start: subscribing agent \(pubkeyHex.prefix(12), privacy: .public)… on \(settings.nostrRelayURL, privacy: .public)"
        )
        stop()
        connectedRelayURL = settings.nostrRelayURL
        Task { [weak self] in
            await self?.openSubscription(agentPubkey: pubkeyHex)
        }
        publishAgentProfileIfPossible()
    }

    /// Tears down the Rust subscription and the multiplexer handle.
    func stop() {
        let id = peerSubscriptionID
        let handle = peerHandle
        peerSubscriptionID = nil
        peerHandle = nil
        connectedRelayURL = nil
        profileFetchInflight.removeAll()
        Task { @MainActor in
            if let id { await PodcastrCoreBridge.shared.core.unsubscribePeerMessages(subId: id) }
            if let handle { PodcastrCoreBridge.shared.unregister(handle) }
        }
    }

    // MARK: - Subscription open

    private func openSubscription(agentPubkey: String) async {
        // Install the read-only public key on the Rust session so the
        // inbound `#p == <my pubkey>` filter is valid and any AUTH
        // challenge from the relay can be answered (the core handles
        // AUTH transparently when a signer is configured; a writable
        // signer is installed separately by the LLM/tool layer via
        // `core.loginNsec` when needed).
        _ = try? PodcastrCoreBridge.shared.core.loginPubkey(npubOrHex: agentPubkey)

        // Register the Swift-side handler BEFORE asking Rust to open the
        // subscription so we don't race a fast EOSE / first event.
        let handle = PodcastrCoreBridge.shared.register { [weak self] delta in
            guard case .peerMessageReceived(let msg) = delta.change else { return }
            Task { @MainActor in self?.handle(inbound: msg) }
        }
        self.peerHandle = handle

        do {
            let id = try await PodcastrCoreBridge.shared.core.subscribePeerMessages(
                since: store.state.nostrSinceCursor.map(Int64.init),
                callbackSubscriptionId: handle.callbackID
            )
            self.peerSubscriptionID = id
            NostrRelayService.logger.notice(
                "openSubscription: peer subscription opened (sub=\(id, privacy: .public))"
            )
        } catch {
            NostrRelayService.logger.error("openSubscription: failed — \(error, privacy: .public)")
            PodcastrCoreBridge.shared.unregister(handle)
            self.peerHandle = nil
        }
    }

    // MARK: - Kind:0 profile publish

    /// Publishes the agent's kind:0 metadata event via the Rust core.
    /// Can be called directly when the user edits profile settings without
    /// restarting the subscription.
    func republishProfile() {
        let settings = store.state.settings
        guard settings.nostrEnabled,
              settings.nostrPublicKeyHex?.isEmpty == false,
              !settings.nostrRelayURL.isEmpty else { return }
        publishAgentProfileIfPossible()
    }

    private func publishAgentProfileIfPossible() {
        let settings = store.state.settings
        let name = settings.nostrProfileName.trimmed
        let about = settings.nostrProfileAbout.trimmed
        let picture = settings.nostrProfilePicture.trimmed
        let effectiveName = name.isEmpty ? "Podcastr Agent" : name
        let aboutPayload: String? = about.isEmpty ? nil : about
        let picturePayload: String? = picture.isEmpty ? nil : picture
        // Settings doesn't currently surface display_name / nip05 / lud16;
        // pass nil so the Rust side omits those fields from the payload
        // rather than writing empty strings.
        //
        // Restore the legacy `["backend", "Podcastr App in <device>"]`
        // event tag so downstream relays / clients can tell which install
        // last touched the profile. The Rust `republishAgentProfile`
        // accepts these as `extraTags`.
        let deviceName = UIDevice.current.name
        let backendTag = ["backend", "Podcastr App in \(deviceName)"]
        Task {
            do {
                _ = try await PodcastrCoreBridge.shared.core.republishAgentProfile(
                    name: effectiveName,
                    displayName: nil,
                    about: aboutPayload,
                    picture: picturePayload,
                    nip05: nil,
                    lud16: nil,
                    extraTags: [backendTag]
                )
            } catch {
                NostrRelayService.logger.error("republishProfile: failed — \(error, privacy: .public)")
            }
        }
    }

    // MARK: - Inbound dispatch

    /// Adapts a Rust `PeerMessageRecord` into the dedup / approval / responder
    /// pipeline. Mirrors the original `handle(text:)` switch but skips the
    /// wire-protocol parsing — the Rust core already did that.
    private func handle(inbound msg: PeerMessageRecord) {
        let eventID = msg.eventId
        let senderPubkey = msg.fromPubkey
        let createdAt = Int(msg.createdAt)
        let content = msg.content

        NostrRelayService.logger.notice(
            "inbound id=\(eventID.prefix(12), privacy: .public) from=\(senderPubkey.prefix(12), privacy: .public)"
        )

        guard senderPubkey != store.state.settings.nostrPublicKeyHex else {
            NostrRelayService.logger.debug("handle: dropping self-authored event")
            return
        }
        guard !store.state.nostrBlockedPubkeys.contains(senderPubkey) else {
            NostrRelayService.logger.notice("handle: dropping event from blocked pubkey")
            return
        }

        // Rust now carries the full tag list and the canonical NIP-01 JSON
        // of the inbound event, so NIP-10 root resolution + delegation
        // routing + transcript-export raw JSON all work end-to-end.
        let inboundTags: [[String]] = msg.tags
        let inboundRawJSON: String? = msg.rawEventJson.isEmpty ? nil : msg.rawEventJson
        let inboundRootID = NostrConversationRoot.rootEventID(
            eventID: eventID,
            tags: inboundTags
        )
        if store.hasPendingFriendMessage(forRootEventID: inboundRootID) {
            NostrRelayService.logger.notice(
                "handle: routing delegation response from \(senderPubkey.prefix(12), privacy: .public) to agent responder"
            )
            ensureProfileFetch(for: senderPubkey)
            agentResponder.handle(inbound: NostrAgentResponder.Inbound(
                eventID: eventID,
                pubkey: senderPubkey,
                createdAt: createdAt,
                content: content,
                tags: inboundTags,
                rawEventJSON: inboundRawJSON
            ))
            return
        }

        if store.state.nostrAllowedPubkeys.contains(senderPubkey) {
            NostrRelayService.logger.notice("handle: routing inbound from allowed pubkey to agent responder")
            // Kick off a kind:0 fetch in parallel so the conversations UI
            // and approval views see the peer's display name + avatar
            // even on follow-up turns the responder doesn't fetch profile
            // for again. The responder runs its own bounded 2s profile
            // race for cold-cache cases; the two fetches are independent
            // (different in-flight guards) and slightly wasteful in the
            // worst case — preferable to leaving the UI cache cold.
            ensureProfileFetch(for: senderPubkey)
            agentResponder.handle(inbound: NostrAgentResponder.Inbound(
                eventID: eventID,
                pubkey: senderPubkey,
                createdAt: createdAt,
                content: content,
                tags: inboundTags,
                rawEventJSON: inboundRawJSON
            ))
            return
        }

        let isNew = !store.state.nostrPendingApprovals.contains { $0.pubkeyHex == senderPubkey }
        NostrRelayService.logger.notice("handle: queueing approval (new=\(isNew, privacy: .public)) for \(senderPubkey.prefix(12), privacy: .public)")
        let cached = store.state.nostrProfileCache[senderPubkey]
        let approval = NostrPendingApproval(
            pubkeyHex: senderPubkey,
            displayName: cached?.bestLabel,
            about: cached?.about,
            pictureURL: cached?.picture,
            content: content
        )
        store.addNostrPendingApproval(approval)
        if isNew {
            Task { await NotificationService.notifyPendingApproval(pubkeyHex: senderPubkey) }
            ensureProfileFetch(for: senderPubkey, enrichApproval: true)
        }
    }

    // MARK: - Profile fetching

    private func ensureProfileFetch(for pubkey: String, enrichApproval: Bool = false) {
        if store.state.nostrProfileCache[pubkey] != nil, !enrichApproval { return }
        guard !profileFetchInflight.contains(pubkey) else { return }
        profileFetchInflight.insert(pubkey)
        Task { [weak self] in
            guard let self else { return }
            await self.profileFetcher.fetchProfiles(for: [pubkey])
            self.profileFetchInflight.remove(pubkey)
            if enrichApproval, let profile = self.store.state.nostrProfileCache[pubkey] {
                self.store.enrichNostrPendingApproval(pubkeyHex: pubkey, from: profile)
            }
        }
    }
}
