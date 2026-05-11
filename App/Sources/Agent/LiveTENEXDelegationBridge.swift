import Foundation
import os.log

// MARK: - LiveTENEXDelegationBridge

/// Persists TENEX-shaped delegate requests and publishes them as kind:1 Nostr
/// events when the app has an agent key and relay configured.
final class LiveTENEXDelegationBridge: PodcastDelegationProtocol, @unchecked Sendable {
    private let logger = Logger.app("AgentTools")
    weak var store: AppStateStore?
    private let outbox: TENEXDelegationOutbox
    private let publisher: NostrEventPublishing

    init(
        store: AppStateStore,
        outbox: TENEXDelegationOutbox = .shared,
        publisher: NostrEventPublishing = NostrWebSocketEventPublisher()
    ) {
        self.store = store
        self.outbox = outbox
        self.publisher = publisher
    }

    func delegate(recipient: String, prompt: String) async throws -> DelegationResult {
        let createdAt = Date()
        let createdAtSeconds = Int(createdAt.timeIntervalSince1970)
        let recipientTag = await recipientPubkeyOrSlug(recipient)
        guard !recipientTag.isEmpty else {
            throw TENEXDelegationPublishError.unresolvableRecipient(recipient)
        }
        let tags = [
            ["p", recipientTag],
            ["a", "31933:09d48a1a5dbe13404a729634f1d6ba722d40513468dd713c8ea38ca9b7b6f2c7:podcast"],
            ["delegation", "podcastr"],
            ["tool", "delegate"],
            ["client", "Podcastr"],
        ]

        let signedEvent = try await signIfPossible(
            prompt: prompt,
            tags: tags,
            createdAt: createdAtSeconds
        )
        let settings = await store?.state.settings
        var status = signedEvent == nil ? "queued_local" : "stored_signed"
        var warning: String?

        if let event = signedEvent,
           settings?.nostrEnabled == true,
           let relay = settings?.nostrRelayURL.trimmed,
           !relay.isEmpty,
           let relayURL = URL(string: relay) {
            do {
                try await publisher.publish(event: event, relayURL: relayURL)
                status = "published"
            } catch {
                warning = "Signed delegation was stored locally but relay publish failed: \(error.localizedDescription)"
                logger.error("delegate publish failed: \(error.localizedDescription, privacy: .public)")
            }
        } else if signedEvent == nil {
            warning = "No agent Nostr key is configured; delegation was stored in the local outbox."
        }

        let result = DelegationResult(
            eventID: signedEvent?.id ?? "local-\(UUID().uuidString)",
            recipient: recipient,
            prompt: prompt,
            status: status,
            createdAt: createdAt,
            tags: tags,
            warning: warning
        )
        try await outbox.record(
            result: result,
            signedEvent: signedEvent,
            relayURL: settings?.nostrRelayURL
        )
        return result
    }

    private func signIfPossible(
        prompt: String,
        tags: [[String]],
        createdAt: Int
    ) async throws -> SignedNostrEvent? {
        guard let key = try NostrCredentialStore.privateKey() else { return nil }
        let pair = try NostrKeyPair(privateKeyHex: key)
        let draft = NostrEventDraft(
            kind: 1,
            content: prompt,
            tags: tags,
            createdAt: createdAt
        )
        return try await LocalKeySigner(keyPair: pair).sign(draft)
    }

    private func recipientPubkeyOrSlug(_ value: String) async -> String {
        let trimmed = value.trimmed
        // Resolve a friend display name to its stored hex pubkey.
        // Must hop to MainActor because AppStateStore is @MainActor-isolated.
        let friends: [Friend] = await MainActor.run { store?.state.friends ?? [] }
        if let match = friends.first(where: { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match.identifier.lowercased()
        }
        if trimmed.count == 64, Data(hexString: trimmed) != nil {
            return trimmed.lowercased()
        }
        if let (hrp, bytes) = Bech32.decode(trimmed),
           hrp == "npub",
           bytes.count == 32 {
            return bytes.hexString
        }
        // No match — fail loudly so the caller surfaces an error rather than
        // publishing a useless slug in the p-tag.
        return ""
    }
}

// MARK: - Local route outbox

actor TENEXDelegationOutbox {
    static let shared = TENEXDelegationOutbox()

    private let fileURL: URL
    private let encoder: JSONEncoder

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? base
            .appendingPathComponent("podcastr-agent", isDirectory: true)
            .appendingPathComponent("delegations.jsonl", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func record(
        result: DelegationResult,
        signedEvent: SignedNostrEvent?,
        relayURL: String?
    ) throws {
        let route = TENEXDelegationRouteRecord(
            eventID: result.eventID,
            recipient: result.recipient,
            status: result.status,
            createdAt: result.createdAt,
            nostrKind: result.nostrKind,
            tags: result.tags,
            relayURL: relayURL,
            signedEvent: signedEvent,
            warning: result.warning
        )
        let data = try encoder.encode(route)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
    }
}

private struct TENEXDelegationRouteRecord: Codable, Sendable {
    let eventID: String
    let recipient: String
    let status: String
    let createdAt: Date
    let nostrKind: Int
    let tags: [[String]]
    let relayURL: String?
    let signedEvent: SignedNostrEvent?
    let warning: String?
}

// MARK: - Nostr publish helper

protocol NostrEventPublishing: Sendable {
    func publish(event: SignedNostrEvent, relayURL: URL) async throws
}

struct NostrWebSocketEventPublisher: NostrEventPublishing {
    func publish(event: SignedNostrEvent, relayURL: URL) async throws {
        let task = URLSession.shared.webSocketTask(with: relayURL)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let message: [Any] = ["EVENT", eventDictionary(event)]
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TENEXDelegationPublishError.encodingFailed
        }
        try await send(text, task: task)
        try await validateRelayAck(for: event.id, task: task)
    }

    private func send(_ text: String, task: URLSessionWebSocketTask) async throws {
        let _: Void = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func validateRelayAck(for eventID: String, task: URLSessionWebSocketTask) async throws {
        let message = try await task.receive()
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 3,
              array[0] as? String == "OK",
              array[1] as? String == eventID else {
            throw TENEXDelegationPublishError.missingOK
        }
        if let accepted = array[2] as? Bool, !accepted {
            let reason = array.count > 3 ? (array[3] as? String) : nil
            throw TENEXDelegationPublishError.rejected(reason ?? "Relay rejected event.")
        }
    }

    private func eventDictionary(_ event: SignedNostrEvent) -> [String: Any] {
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
}

enum TENEXDelegationPublishError: LocalizedError {
    case encodingFailed
    case missingOK
    case rejected(String)
    case unresolvableRecipient(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Could not encode Nostr EVENT message."
        case .missingOK: return "Relay did not acknowledge the delegation event."
        case .rejected(let reason): return reason
        case .unresolvableRecipient(let name):
            return "'\(name)' is not a known friend name, hex pubkey, or npub. Add them to Friends first."
        }
    }
}
