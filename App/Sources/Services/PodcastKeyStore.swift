import Foundation

/// Stores per-podcast Nostr private keys in Keychain.
///
/// Each podcast published via NIP-F4 has its own Nostr identity — the podcast
/// IS a keypair, not just a tagged event from the agent's key. Keys are keyed
/// by the podcast's local UUID so they survive relay migrations and re-publishes.
enum PodcastKeyStore {

    private static let service = "\(Bundle.main.bundleIdentifier ?? "Podcastr").nostr"

    private static func account(for podcastID: UUID) -> String {
        "podcast-privkey-\(podcastID.uuidString.lowercased())"
    }

    static func savePrivateKey(_ hex: String, podcastID: UUID) throws {
        try KeychainStore.saveString(hex, service: service, account: account(for: podcastID))
    }

    static func privateKey(podcastID: UUID) throws -> String? {
        try KeychainStore.readString(service: service, account: account(for: podcastID))
    }

    static func deletePrivateKey(podcastID: UUID) throws {
        try KeychainStore.deleteString(service: service, account: account(for: podcastID))
    }
}
