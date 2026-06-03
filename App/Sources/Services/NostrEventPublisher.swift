import Foundation

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
