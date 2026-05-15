import Foundation
import Observation
import os.log

/// A single relay WebSocket connection. Adapted from `NostrRelayService`:
/// carries forward NIP-42 AUTH, reconnect-with-backoff, and the JSON-frame
/// wire protocol; adds subscription management, per-event publish acks,
/// and basic diagnostics.
@MainActor
@Observable
final class RelayConnection: Identifiable {
    nonisolated static let logger = Logger.app("RelayConnection")

    let url: String
    let signer: any NostrSigner

    private(set) var status: ConnectionStatus = .disconnected
    private(set) var rtt: TimeInterval?
    private(set) var bytesReceived: Int = 0
    private(set) var bytesSent: Int = 0
    private(set) var lastError: String?

    nonisolated var id: String { url }

    enum ConnectionStatus: Equatable {
        case disconnected, connecting, connected, authenticating
        case error(String)
        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    struct PublishResult: Sendable {
        let success: Bool
        let message: String?
    }

    struct Subscription {
        let filter: [[String: Any]]
        let handler: (SignedNostrEvent) -> Void
        var sentAt: Date?
        var rttRecorded: Bool
    }
    // Internal plumbing — visibility widened from `private` so the AUTH
    // extension in `RelayConnection+Auth.swift` can re-issue REQs and
    // re-send pending publishes after a successful NIP-42 handshake.
    // `@ObservationIgnored` keeps these out of `@Observable` tracking so
    // SwiftUI never tries to diff a dict whose values contain closures.
    @ObservationIgnored var subscriptions: [String: Subscription] = [:]
    @ObservationIgnored var pendingPublishes: [String: CheckedContinuation<PublishResult, Never>] = [:]
    @ObservationIgnored var pendingPublishEvents: [String: SignedNostrEvent] = [:]
    @ObservationIgnored var pendingAuthEventIDs: Set<String> = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var reconnectBackoff: TimeInterval = 5
    private var explicitlyDisconnected = false
    private static let backoffCap: TimeInterval = 60

    init(url: String, signer: any NostrSigner) {
        self.url = url
        self.signer = signer
    }

    func connect() async {
        explicitlyDisconnected = false
        guard let urlObj = URL(string: url) else {
            status = .error("Invalid URL")
            return
        }
        status = .connecting
        let task = URLSession.shared.webSocketTask(with: urlObj)
        webSocketTask = task
        task.resume()
        status = .connected
        reconnectBackoff = 5
        startReceiveLoop()
        // Re-issue any subscriptions registered while disconnected (or surviving a reconnect).
        for (subID, sub) in subscriptions {
            subscriptions[subID]?.sentAt = Date()
            subscriptions[subID]?.rttRecorded = false
            sendREQ(id: subID, filter: sub.filter)
        }
    }

    func disconnect() {
        explicitlyDisconnected = true
        receiveLoop?.cancel()
        receiveLoop = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        status = .disconnected
        failPendingPublishes(reason: "Disconnected")
    }

    /// Resume every awaiting `send(event:)` caller with a failure result and
    /// clear all transient send-side state. Called from `disconnect()`,
    /// `scheduleReconnect()`, and the AUTH-failure paths in
    /// `RelayConnection+Auth.swift` so the WebSocket teardown never leaves a
    /// continuation stranded.
    func failPendingPublishes(reason: String) {
        for (_, continuation) in pendingPublishes {
            continuation.resume(returning: PublishResult(success: false, message: reason))
        }
        pendingPublishes.removeAll()
        pendingPublishEvents.removeAll()
        pendingAuthEventIDs.removeAll()
    }

    // MARK: - Subscriptions

    func subscribe(id: String, filter: [[String: Any]], handler: @escaping (SignedNostrEvent) -> Void) {
        let sub = Subscription(filter: filter, handler: handler, sentAt: Date(), rttRecorded: false)
        subscriptions[id] = sub
        if webSocketTask != nil {
            sendREQ(id: id, filter: filter)
        }
    }

    func unsubscribe(id: String) {
        guard subscriptions.removeValue(forKey: id) != nil else { return }
        sendFrame(["CLOSE", id])
    }

    func send(event: SignedNostrEvent) async -> PublishResult {
        guard webSocketTask != nil else {
            return PublishResult(success: false, message: "Not connected")
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<PublishResult, Never>) in
            pendingPublishes[event.id] = cont
            pendingPublishEvents[event.id] = event
            sendFrame(["EVENT", eventDict(event)])
        }
    }

    func sendREQ(id: String, filter: [[String: Any]]) {
        var frame: [Any] = ["REQ", id]
        for f in filter { frame.append(f) }
        sendFrame(frame)
    }

    func sendFrame(_ frame: [Any]) {
        guard let task = webSocketTask else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: frame)
            guard let text = String(data: data, encoding: .utf8) else { return }
            bytesSent += data.count
            task.send(.string(text)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.lastError = error.localizedDescription }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func eventDict(_ event: SignedNostrEvent) -> [String: Any] {
        [
            "id": event.id,
            "pubkey": event.pubkey,
            "created_at": event.created_at,
            "kind": event.kind,
            "tags": event.tags,
            "content": event.content,
            "sig": event.sig,
        ]
    }

    private func startReceiveLoop() {
        receiveLoop = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask else { return }
                do {
                    let msg = try await task.receive()
                    switch msg {
                    case .string(let text):
                        self.bytesReceived += text.utf8.count
                        self.handle(text: text)
                    case .data(let d):
                        self.bytesReceived += d.count
                    @unknown default:
                        break
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    guard !self.explicitlyDisconnected else { return }
                    self.lastError = error.localizedDescription
                    self.status = .error(error.localizedDescription)
                    await self.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func scheduleReconnect() async {
        let delay = reconnectBackoff
        reconnectBackoff = min(Self.backoffCap, reconnectBackoff * 2)
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        failPendingPublishes(reason: "Disconnected")
        try? await Task.sleep(for: .seconds(delay))
        guard !explicitlyDisconnected else { return }
        await connect()
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              !array.isEmpty,
              let msgType = array[0] as? String else { return }
        switch msgType {
        case "EVENT": handleEvent(array)
        case "EOSE": handleEose(array)
        case "OK": handleOK(array)
        case "AUTH": handleAuthChallenge(array)
        case "NOTICE", "CLOSED":
            Self.logger.notice("\(self.url, privacy: .public) \(msgType, privacy: .public): \(text, privacy: .public)")
        default: break
        }
    }

    private func handleEvent(_ array: [Any]) {
        guard array.count >= 3,
              let subID = array[1] as? String,
              let dict = array[2] as? [String: Any] else { return }
        recordRTT(subID: subID)
        guard let event = parseEvent(dict) else { return }
        subscriptions[subID]?.handler(event)
    }

    private func handleEose(_ array: [Any]) {
        guard array.count >= 2, let subID = array[1] as? String else { return }
        recordRTT(subID: subID)
    }

    func recordRTT(subID: String) {
        guard var sub = subscriptions[subID], !sub.rttRecorded, let sentAt = sub.sentAt else { return }
        rtt = Date().timeIntervalSince(sentAt)
        sub.rttRecorded = true
        subscriptions[subID] = sub
    }

    private func parseEvent(_ dict: [String: Any]) -> SignedNostrEvent? {
        guard let id = dict["id"] as? String,
              let pubkey = dict["pubkey"] as? String,
              let createdAt = dict["created_at"] as? Int,
              let kind = dict["kind"] as? Int,
              let content = dict["content"] as? String,
              let sig = dict["sig"] as? String,
              let tags = dict["tags"] as? [[String]] else { return nil }
        return SignedNostrEvent(
            id: id, pubkey: pubkey, created_at: createdAt,
            kind: kind, tags: tags, content: content, sig: sig
        )
    }

    func handleOK(_ array: [Any]) {
        guard array.count >= 3,
              let eventID = array[1] as? String,
              let accepted = array[2] as? Bool else { return }
        let message = array.count >= 4 ? array[3] as? String : nil
        if pendingAuthEventIDs.remove(eventID) != nil {
            handleAuthOK(accepted: accepted, message: message)
            return
        }
        // `OK false auth-required: ...` — leave the event + continuation in
        // place so the AUTH replay (see `RelayConnection+Auth.handleAuthOK`)
        // can resend it. A subsequent OK on the same id resolves the caller.
        if !accepted, let message, message.hasPrefix("auth-required") {
            return
        }
        if let cont = pendingPublishes.removeValue(forKey: eventID) {
            pendingPublishEvents.removeValue(forKey: eventID)
            cont.resume(returning: PublishResult(success: accepted, message: message))
        }
    }

    // NIP-42 status updates need to mutate `status` (private(set)) from the
    // AUTH extension below — expose a helper instead of widening access.
    func setStatus(_ newStatus: ConnectionStatus) { status = newStatus }
}
