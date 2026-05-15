import Foundation

// MARK: - NostrEventPublishing
//
// Shared one-shot publisher used by lightweight Nostr writers that don't want
// to take a long-lived `NostrRelayService` dependency (e.g. the agent
// peer-tools surface). With the Rust core in place, "publish" now means:
// hand the already-signed event JSON to the Rust pool, which broadcasts it
// to every configured writer relay. The `relayURL` argument is preserved
// for source compatibility but is no longer consulted.

protocol NostrEventPublishing: Sendable {
    func publish(event: SignedNostrEvent, relayURL: URL) async throws
}

struct NostrWebSocketEventPublisher: NostrEventPublishing {
    func publish(event: SignedNostrEvent, relayURL: URL) async throws {
        // rust-cutover: relayURL ignored; Rust pool broadcasts to all writers
        let jsonString: String
        do {
            let payload = try JSONSerialization.data(
                withJSONObject: Self.eventDictionary(event),
                options: []
            )
            guard let text = String(data: payload, encoding: .utf8) else {
                throw NostrEventPublisherError.encodingFailed
            }
            jsonString = text
        } catch let err as NostrEventPublisherError {
            throw err
        } catch {
            throw NostrEventPublisherError.encodingFailed
        }

        do {
            _ = try await PodcastrCoreBridge.shared.core.publishSignedEventJson(
                eventJson: jsonString
            )
        } catch {
            // Funnel any Rust-side failure (signature reject, no relays, etc.)
            // through the existing `.rejected` case so callers' `LocalizedError`
            // handling continues to surface a human-readable message.
            throw NostrEventPublisherError.rejected(error.localizedDescription)
        }
    }

    /// Serialises a `SignedNostrEvent` into the exact JSON object shape the
    /// Rust core expects (`publishSignedEventJson` parses it back into its
    /// internal event type, then re-broadcasts).
    private static func eventDictionary(_ event: SignedNostrEvent) -> [String: Any] {
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
