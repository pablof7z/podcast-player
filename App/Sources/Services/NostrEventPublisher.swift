import Foundation
@preconcurrency import NDKSwiftCore
import os.log

// MARK: - NostrEventPublishing
//
// One-shot publisher used by the agent peer-tools surface and a handful of
// service-level callers that don't take a long-lived `NostrRelayService`
// dependency. The protocol predates the NDKSwift migration — the type name
// (`NostrWebSocketEventPublisher`) is retained for API stability even
// though the implementation now routes through the shared `NDK` instance
// owned by `NostrStack.shared`. There is no transient WebSocket anymore;
// `ndk.publish(_:to:)` reuses the relay pool and adds the target relay if
// it isn't already in the pool.

protocol NostrEventPublishing: Sendable {
    func publish(event: SignedNostrEvent, relayURL: URL) async throws
}

struct NostrWebSocketEventPublisher: NostrEventPublishing {
    private static let logger = Logger.app("NostrEventPublisher")

    func publish(event: SignedNostrEvent, relayURL: URL) async throws {
        guard let ndk = await NostrStack.shared.ndk else {
            throw NostrEventPublisherError.noRelayConfigured
        }
        let ndkEvent = ndkEvent(from: event)
        let target = relayURL.absoluteString
        Self.logger.debug("publish: event \(event.id.prefix(8), privacy: .public) kind=\(event.kind) → \(target, privacy: .public)")
        let accepted: Set<NDKRelay>
        do {
            accepted = try await ndk.publish(ndkEvent, to: [target])
        } catch {
            throw NostrEventPublisherError.rejected(error.localizedDescription)
        }
        if accepted.isEmpty {
            // NDK returns empty either because no relay accepted, or because
            // the pool wasn't connected yet (event got queued offline). The
            // existing callers treated "no OK frame" as an error, so preserve
            // that strict semantic for one-shot publishes.
            Self.logger.warning("publish: no relay accepted event \(event.id.prefix(8), privacy: .public) for \(target, privacy: .public)")
            throw NostrEventPublisherError.missingOK
        }
    }

    // MARK: - SignedNostrEvent → NDKEvent

    /// Re-hydrates an already-signed in-app event into the NDK value type.
    /// All identity / signature fields are preserved verbatim — NDK does not
    /// re-sign or re-canonicalize; it just forwards the wire bytes.
    private func ndkEvent(from event: SignedNostrEvent) -> NDKEvent {
        NDKEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: Timestamp(event.created_at),
            kind: Kind(event.kind),
            tags: event.tags,
            content: event.content,
            sig: event.sig
        )
    }
}

enum NostrEventPublisherError: LocalizedError {
    case encodingFailed
    case missingOK
    case rejected(String)
    case noRelayConfigured
    case noSigningKey

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Could not encode Nostr EVENT message."
        case .missingOK: return "Relay did not acknowledge the event."
        case .rejected(let reason): return reason
        case .noRelayConfigured: return "No Nostr relay is configured."
        case .noSigningKey: return "No Nostr signing key is available."
        }
    }
}
