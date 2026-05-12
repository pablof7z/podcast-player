import Foundation
import os.log
import UIKit

/// Connects to a configured Nostr relay and gates incoming kind:1 messages
/// through the access-control layer, queuing unknown senders for user approval.
@MainActor
final class NostrRelayService {
    nonisolated private static let logger = Logger.app("NostrRelayService")
    private let store: AppStateStore
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var connectedRelayURL: String?
    private lazy var profileFetcher = NostrProfileFetcher(store: store)
    /// Tracks pubkeys we've already queued a profile fetch for during this
    /// session so a burst of inbound events from the same peer doesn't
    /// spam the relay with kind:0 requests. Cleared on `stop()`.
    private var profileFetchInflight: Set<String> = []

    // MARK: - Protocol constants

    private enum NostrProtocol {
        static let requestCommand = "REQ"
        static let eventMessage = "EVENT"
        static let kindTextNote = 1
        static let minEventArrayCount = 3
        static let eventIndex = 2
        static let subscriptionID = "agent-inbox"
        static let reconnectDelay: Duration = .seconds(5)
    }

    /// Creates a new service backed by the given state store.
    init(store: AppStateStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    /// Reads the current Nostr settings and connects to the configured relay,
    /// or stops the service if Nostr is disabled or misconfigured.
    func start() {
        let settings = store.state.settings
        guard settings.nostrEnabled,
              let pubkeyHex = settings.nostrPublicKeyHex, !pubkeyHex.isEmpty,
              !settings.nostrRelayURL.isEmpty else {
            stop()
            return
        }
        guard connectedRelayURL != settings.nostrRelayURL || webSocketTask == nil else { return }
        stop()
        connect(urlString: settings.nostrRelayURL, agentPubkey: pubkeyHex)
    }

    /// Cancels the receive loop and closes the WebSocket connection.
    func stop() {
        receiveLoop?.cancel()
        receiveLoop = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectedRelayURL = nil
        profileFetchInflight.removeAll()
    }

    // MARK: - Connection

    private func connect(urlString: String, agentPubkey: String) {
        guard let url = URL(string: urlString) else {
            NostrRelayService.logger.error("NostrRelayService: invalid relay URL '\(urlString, privacy: .public)'")
            return
        }
        connectedRelayURL = urlString
        NostrRelayService.logger.info("NostrRelayService: connecting to \(urlString, privacy: .public)")
        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        sendSubscription(agentPubkey: agentPubkey)
        startReceiveLoop(agentPubkey: agentPubkey)
        publishAgentProfileIfPossible(relayURL: url)
    }

    // MARK: - Kind:0 profile publish

    /// Publishes the agent's kind:0 metadata event to the configured relay.
    /// Can be called directly when the user edits profile settings without
    /// restarting the relay connection.
    func republishProfile() {
        let settings = store.state.settings
        guard settings.nostrEnabled,
              settings.nostrPublicKeyHex?.isEmpty == false,
              !settings.nostrRelayURL.isEmpty,
              let relayURL = URL(string: settings.nostrRelayURL) else { return }
        publishAgentProfileIfPossible(relayURL: relayURL)
    }

    private func publishAgentProfileIfPossible(relayURL: URL) {
        let settings = store.state.settings
        let name = settings.nostrProfileName.trimmed
        let about = settings.nostrProfileAbout.trimmed
        let picture = settings.nostrProfilePicture.trimmed
        let effectiveName = name.isEmpty ? "Podcastr Agent" : name
        let deviceName = UIDevice.current.name

        Task {
            guard let privKey = try? NostrCredentialStore.privateKey() else { return }
            guard let pair = try? NostrKeyPair(privateKeyHex: privKey) else { return }
            var metadata: [String: String] = ["name": effectiveName, "about": about]
            if !picture.isEmpty { metadata["picture"] = picture }
            guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
                  let content = String(data: data, encoding: .utf8) else { return }
            let draft = NostrEventDraft(kind: 0, content: content, tags: [["backend", "Podcastr App in \(deviceName)"]])
            guard let event = try? await LocalKeySigner(keyPair: pair).sign(draft) else { return }
            let publisher = NostrWebSocketEventPublisher()
            try? await publisher.publish(event: event, relayURL: relayURL)
        }
    }

    private func sendSubscription(agentPubkey: String) {
        let filter: [String: Any] = [
            "kinds": [NostrProtocol.kindTextNote],
            "#p": [agentPubkey],
        ]
        let message: [Any] = [NostrProtocol.requestCommand, NostrProtocol.subscriptionID, filter]
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            guard let text = String(data: data, encoding: .utf8) else {
                NostrRelayService.logger.error("sendSubscription: failed to encode REQ as UTF-8 string")
                return
            }
            webSocketTask?.send(.string(text)) { error in
                if let error {
                    NostrRelayService.logger.error("sendSubscription: WebSocket send failed — \(error, privacy: .public)")
                }
            }
        } catch {
            NostrRelayService.logger.error("sendSubscription: JSON serialization failed — \(error, privacy: .public)")
        }
    }

    private func startReceiveLoop(agentPubkey: String) {
        receiveLoop = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask else { return }
                do {
                    let msg = try await task.receive()
                    if case .string(let text) = msg { self.handle(text: text) }
                } catch {
                    guard !Task.isCancelled else { return }
                    NostrRelayService.logger.warning("NostrRelayService: WebSocket error — \(error, privacy: .public); reconnecting in \(NostrProtocol.reconnectDelay)")
                    // Cancellation is checked immediately after; swallowing the sleep-cancel error is intentional.
                    try? await Task.sleep(for: NostrProtocol.reconnectDelay)
                    guard !Task.isCancelled else { return }
                    self.start()
                    return
                }
            }
        }
    }

    // MARK: - Event handling

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= NostrProtocol.minEventArrayCount,
              let msgType = array[0] as? String, msgType == NostrProtocol.eventMessage,
              let event = array[NostrProtocol.eventIndex] as? [String: Any],
              let kind = event["kind"] as? Int, kind == NostrProtocol.kindTextNote,
              let senderPubkey = event["pubkey"] as? String else { return }

        guard senderPubkey != store.state.settings.nostrPublicKeyHex else { return }
        guard !store.state.nostrBlockedPubkeys.contains(senderPubkey) else { return }

        if store.state.nostrAllowedPubkeys.contains(senderPubkey) {
            recordIncomingTurn(event: event, senderPubkey: senderPubkey, rawText: text)
            // TODO: route to the agent pipeline (LLM reply + outgoing publish).
            // When that lands it should call
            // `store.recordNostrTurn(rootEventID:turn:counterpartyPubkey:)`
            // with the outgoing event so the transcript stays complete.
            ensureProfileFetch(for: senderPubkey)
            return
        }

        let isNew = !store.state.nostrPendingApprovals.contains { $0.pubkeyHex == senderPubkey }
        let cached = store.state.nostrProfileCache[senderPubkey]
        let approval = NostrPendingApproval(
            pubkeyHex: senderPubkey,
            displayName: cached?.bestLabel,
            about: cached?.about,
            pictureURL: cached?.picture,
            content: event["content"] as? String
        )
        store.addNostrPendingApproval(approval)
        if isNew {
            Task { await NotificationService.notifyPendingApproval(pubkeyHex: senderPubkey) }
            ensureProfileFetch(for: senderPubkey, enrichApproval: true)
        }
    }

    // MARK: - Conversation recording

    private func recordIncomingTurn(
        event: [String: Any],
        senderPubkey: String,
        rawText: String
    ) {
        guard let eventID = event["id"] as? String,
              let createdAtSeconds = event["created_at"] as? Int else { return }
        let content = (event["content"] as? String) ?? ""
        let tags = (event["tags"] as? [[String]]) ?? []
        let rootID = NostrConversationRoot.rootEventID(eventID: eventID, tags: tags)

        let rawJSON = (try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }

        let turn = NostrConversationTurn(
            eventID: eventID,
            direction: .incoming,
            pubkey: senderPubkey,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAtSeconds)),
            content: content,
            rawEventJSON: rawJSON
        )
        store.recordNostrTurn(rootEventID: rootID, turn: turn)
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
