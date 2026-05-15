import Foundation
@preconcurrency import NDKSwiftCore
import os.log
import UIKit

/// Drains the agent's NDK inbox subscription, applies the access-control
/// pre-filter, and dispatches qualifying events to `NostrAgentResponder`.
///
/// Wire model: this service does not own a WebSocket — `NostrStack.shared`
/// owns the process-wide `NDK` and its relay pool. We gate on
/// `relaysConnected` and open an ongoing `NDKSubscription` against the
/// shared NDK. NIP-42 AUTH is handled by NDK automatically once
/// `ndk.signer` is set to the agent's local key (see `setAgentSignerIfNeeded`).
///
/// Idempotency: settings-driven `start()` may be called repeatedly. The
/// service holds a single in-flight subscription keyed by agent pubkey;
/// re-calls with the same pubkey are no-ops, with a different pubkey
/// they tear down and re-open.
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

    /// The current inbox subscription against the shared NDK. Held so
    /// `stop()` can close it cleanly; replaced when the agent pubkey
    /// changes (settings flip).
    private var inboxSubscription: NDKSubscription<NDKEvent>?
    /// Task draining the subscription's `events` AsyncStream. Cancelled
    /// on `stop()` and on subscription teardown.
    private var inboxTask: Task<Void, Never>?
    /// Agent pubkey of the live subscription. Used to detect a settings
    /// change that requires re-opening with a different `#p` filter.
    private var subscribedAgentPubkey: String?

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

    private enum Wire {
        static let kindTextNote = 1
        static let subscriptionID = "agent-inbox"
    }

    /// Creates a new service backed by the given state store.
    /// `askCoordinator` is wired through to the lazy `agentResponder` on
    /// first access so peer-initiated `ask` tool calls can pop the
    /// owner-consent sheet from cold-launch onward.
    init(store: AppStateStore, askCoordinator: AgentAskCoordinator? = nil) {
        self.store = store
        self.askCoordinator = askCoordinator
    }

    // MARK: - Lifecycle

    /// Reads the current Nostr settings and opens (or refreshes) the
    /// agent inbox subscription against the shared NDK. Idempotent.
    ///
    /// Preconditions for opening a subscription:
    /// 1. `nostrEnabled == true` and the configured pubkey is non-empty.
    /// 2. `NostrStack.shared.relaysConnected == true` — the relay pool is
    ///    live. If it isn't, we tear down any stale subscription and
    ///    return; `NostrStack.start()` runs in parallel and the next
    ///    `start()` invocation (e.g. driven by `onChange` in AppMain)
    ///    will re-attempt. Reactive, not polling.
    func start() {
        let settings = store.state.settings
        guard settings.nostrEnabled,
              let pubkeyHex = settings.nostrPublicKeyHex, !pubkeyHex.isEmpty,
              !settings.nostrRelayURL.isEmpty else {
            Self.logger.notice(
                "start: skipping — enabled=\(settings.nostrEnabled, privacy: .public), hasPubkey=\(settings.nostrPublicKeyHex?.isEmpty == false, privacy: .public), relayURL='\(settings.nostrRelayURL, privacy: .public)'"
            )
            stop()
            return
        }
        guard NostrStack.shared.relaysConnected, let ndk = NostrStack.shared.ndk else {
            Self.logger.notice("start: NostrStack relays not connected yet; tearing down and waiting")
            stop()
            return
        }
        // Already subscribed for this exact agent — nothing to do.
        if let active = subscribedAgentPubkey, active == pubkeyHex, inboxTask != nil {
            Self.logger.debug("start: already subscribed for \(pubkeyHex.prefix(12), privacy: .public); no-op")
            return
        }

        Self.logger.notice(
            "start: opening inbox subscription for agent \(pubkeyHex.prefix(12), privacy: .public)"
        )
        stop()
        Task { [weak self] in
            await self?.openSubscription(ndk: ndk, agentPubkey: pubkeyHex)
            await self?.publishAgentProfileIfPossible()
        }
    }

    /// Closes the inbox subscription and cancels the draining task. Does
    /// not touch the shared NDK relay pool (NostrStack owns that).
    func stop() {
        inboxTask?.cancel()
        inboxTask = nil
        if let sub = inboxSubscription {
            Task { await sub.close() }
        }
        inboxSubscription = nil
        subscribedAgentPubkey = nil
        profileFetchInflight.removeAll()
    }

    // MARK: - Subscription wiring

    private func openSubscription(ndk: NDK, agentPubkey: String) async {
        // Ensure NDK can sign NIP-42 AUTH challenges with the agent key.
        // NDKSwift auto-responds to `["AUTH", challenge]` when `ndk.signer`
        // is set (default behaviour, see NDK.handleAuthChallenge). With no
        // signer it silently declines and auth-gated relays drop our REQ.
        await setAgentSignerIfNeeded(ndk: ndk)

        // NIP-10 parity: carry `since:` from the persisted cursor so a
        // reconnecting agent doesn't have to chew through every kind:1
        // the relay has ever seen tagged to it. The dedup set
        // (`nostrRespondedEventIDs`) protects against the tiny overlap
        // when an event with `created_at == cursor` is re-delivered.
        let sinceCursor: Timestamp? = store.state.nostrSinceCursor.map { Timestamp($0) }
        let filter = NDKFilter(
            kinds: [Wire.kindTextNote],
            since: sinceCursor,
            tags: ["p": Set([agentPubkey])]
        )
        // `closeOnEose: false` keeps the subscription open for live
        // events after the historical replay completes — this is the
        // ongoing inbox pattern. NDK re-issues the REQ internally if
        // the relay reconnects, so we don't need a manual reconnect
        // loop here.
        let subscription = ndk.subscribe(
            filter: filter,
            subscriptionId: Wire.subscriptionID,
            closeOnEose: false
        )
        inboxSubscription = subscription
        subscribedAgentPubkey = agentPubkey

        // Capture the agent pubkey in the task so a cancelled-but-not-yet-
        // drained subscription that yields one more batch after `stop()`
        // can't leak old-identity events into a freshly-started one.
        let expectedAgent = agentPubkey
        inboxTask = Task { [weak self] in
            for await batch in subscription.events {
                guard let self else { return }
                let stillCurrent = await self.isCurrent(agentPubkey: expectedAgent)
                guard stillCurrent else { return }
                for event in batch {
                    await self.routeInbound(event: event)
                }
            }
        }
    }

    /// Returns true if the live subscription is still bound to the given
    /// agent pubkey. Used by the draining task to bail when `stop()`
    /// (or a re-`start()` with a different identity) has invalidated it.
    private func isCurrent(agentPubkey: String) -> Bool {
        subscribedAgentPubkey == agentPubkey
    }

    /// Sets `ndk.signer` to a local key signer wrapping the agent's
    /// private key, so NDKSwift can auto-respond to relay AUTH challenges.
    /// No-op if already set or if the keychain read fails.
    private func setAgentSignerIfNeeded(ndk: NDK) async {
        if ndk.signer != nil { return }
        let privKey: String?
        do { privKey = try NostrCredentialStore.privateKey() } catch {
            Self.logger.error("setAgentSignerIfNeeded: keychain read failed — \(error, privacy: .public)")
            return
        }
        guard let privKey else {
            Self.logger.notice("setAgentSignerIfNeeded: no local private key; NIP-42 AUTH will be declined")
            return
        }
        do {
            let signer = try NDKPrivateKeySigner(privateKey: privKey)
            ndk.signer = signer
            Self.logger.notice("setAgentSignerIfNeeded: ndk.signer set to agent local key")
        } catch {
            Self.logger.error("setAgentSignerIfNeeded: signer init failed — \(error, privacy: .public)")
        }
    }

    // MARK: - Kind:0 profile publish

    /// Publishes the agent's kind:0 metadata event to the configured relay.
    /// Can be called directly when the user edits profile settings without
    /// restarting the relay connection.
    func republishProfile() {
        let settings = store.state.settings
        guard settings.nostrEnabled,
              settings.nostrPublicKeyHex?.isEmpty == false,
              !settings.nostrRelayURL.isEmpty else { return }
        Task { [weak self] in await self?.publishAgentProfileIfPossible() }
    }

    private func publishAgentProfileIfPossible() async {
        let settings = store.state.settings
        let name = settings.nostrProfileName.trimmed
        let about = settings.nostrProfileAbout.trimmed
        let picture = settings.nostrProfilePicture.trimmed
        let effectiveName = name.isEmpty ? "Podcastr Agent" : name
        let deviceName = UIDevice.current.name

        guard let ndk = NostrStack.shared.ndk else {
            Self.logger.notice("publishAgentProfile: no NDK; skipping")
            return
        }
        let privKey: String?
        do { privKey = try NostrCredentialStore.privateKey() } catch {
            Self.logger.error("publishAgentProfile: keychain read failed — \(error, privacy: .public)")
            return
        }
        guard let privKey else {
            Self.logger.notice("publishAgentProfile: no local private key; skipping")
            return
        }
        let signer: LocalKeySigner
        do { signer = try LocalKeySigner(privateKeyHex: privKey) } catch {
            Self.logger.error("publishAgentProfile: signer init failed — \(error, privacy: .public)")
            return
        }
        var metadata: [String: String] = ["name": effectiveName, "about": about]
        if !picture.isEmpty { metadata["picture"] = picture }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
              let content = String(data: data, encoding: .utf8) else {
            Self.logger.error("publishAgentProfile: metadata JSON encode failed")
            return
        }
        let draft = NostrEventDraft(
            kind: 0,
            content: content,
            tags: [["backend", "Podcastr App in \(deviceName)"]]
        )
        let signed: SignedNostrEvent
        do {
            signed = try await signer.sign(draft)
        } catch {
            Self.logger.error("publishAgentProfile: signing failed — \(error, privacy: .public)")
            return
        }
        do {
            let event = NDKEventConverter.toNDKEvent(signed)
            _ = try await ndk.publish(event)
            Self.logger.notice("publishAgentProfile: published kind:0 \(signed.id.prefix(12), privacy: .public)")
        } catch {
            Self.logger.error("publishAgentProfile: publish failed — \(error, privacy: .public)")
        }
    }

    // MARK: - Event routing

    private func routeInbound(event: NDKEvent) async {
        let eventID = event.id
        let senderPubkey = event.pubkey
        let kind = event.kind
        let tags = event.tags
        let content = event.content
        let createdAt = Int(event.createdAt)

        Self.logger.notice(
            "inbound kind=\(kind, privacy: .public) id=\(eventID.prefix(12), privacy: .public) from=\(senderPubkey.prefix(12), privacy: .public)"
        )

        guard kind == Wire.kindTextNote else { return }
        guard senderPubkey != store.state.settings.nostrPublicKeyHex else {
            Self.logger.debug("routeInbound: dropping self-authored event")
            return
        }
        guard !store.state.nostrBlockedPubkeys.contains(senderPubkey) else {
            Self.logger.notice("routeInbound: dropping event from blocked pubkey")
            return
        }

        let rawJSON = rawEventJSON(from: event)

        // Delegation responses: a reply to one of our `send_friend_message`
        // root events. Route directly to the responder without requiring the
        // sender to be in the allowlist — the pending-message registry acts
        // as the authorization gate.
        let inboundRootID = NostrConversationRoot.rootEventID(eventID: eventID, tags: tags)
        if store.hasPendingFriendMessage(forRootEventID: inboundRootID) {
            Self.logger.notice(
                "routeInbound: routing delegation response from \(senderPubkey.prefix(12), privacy: .public) to agent responder"
            )
            ensureProfileFetch(for: senderPubkey)
            agentResponder.handle(inbound: NostrAgentResponder.Inbound(
                eventID: eventID,
                pubkey: senderPubkey,
                createdAt: createdAt,
                content: content,
                tags: tags,
                rawEventJSON: rawJSON
            ))
            return
        }

        if store.state.nostrAllowedPubkeys.contains(senderPubkey) {
            Self.logger.notice("routeInbound: routing inbound from allowed pubkey to agent responder")
            // Kick off a kind:0 fetch in parallel with the responder so
            // the conversations UI and approval views see the peer's
            // display name + avatar even when this inbound is a follow-
            // up turn the responder doesn't need to fetch profile for
            // again. The responder runs its own bounded 2s profile
            // race for cold-cache cases; the two fetches are independent
            // (different in-flight guards) and slightly wasteful in the
            // worst case — preferable to leaving the UI cache cold.
            ensureProfileFetch(for: senderPubkey)
            agentResponder.handle(inbound: NostrAgentResponder.Inbound(
                eventID: eventID,
                pubkey: senderPubkey,
                createdAt: createdAt,
                content: content,
                tags: tags,
                rawEventJSON: rawJSON
            ))
            return
        }

        let isNew = !store.state.nostrPendingApprovals.contains { $0.pubkeyHex == senderPubkey }
        Self.logger.notice("routeInbound: queueing approval (new=\(isNew, privacy: .public)) for \(senderPubkey.prefix(12), privacy: .public)")
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

    // MARK: - Event JSON helper

    /// Re-serialise an NDK event to canonical JSON for transcript export.
    /// Returns nil on failure — the conversation store accepts nil here.
    private nonisolated func rawEventJSON(from event: NDKEvent) -> String? {
        (try? JSONSerialization.data(withJSONObject: event.rawEvent(), options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }
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

