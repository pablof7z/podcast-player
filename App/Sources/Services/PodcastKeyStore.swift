import Foundation
import os.log

/// Stores per-podcast Nostr private keys for NIP-F4 publishing.
enum PodcastKeyStore {
    private static let logger = Logger.app("PodcastKeyStore")
    private static let service = "\(Bundle.main.bundleIdentifier ?? "Pod0").nostr"

    static func savePrivateKey(_ hex: String, podcastID: UUID) throws {
        let trimmed = hex.trimmed
        guard !trimmed.isEmpty else { return }
        try KeychainStore.saveString(trimmed, service: service, account: account(podcastID))
    }

    static func privateKey(podcastID: UUID) throws -> String? {
        guard let value = try KeychainStore.readString(service: service, account: account(podcastID)) else {
            return nil
        }
        let trimmed = value.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    static func deletePrivateKey(podcastID: UUID) throws {
        try KeychainStore.deleteString(service: service, account: account(podcastID))
    }

    static func keyPair(for podcastID: UUID) throws -> NostrKeyPair {
        if let privateKey = try privateKey(podcastID: podcastID) {
            return try NostrKeyPair(privateKeyHex: privateKey)
        }
        let generated = try NostrKeyPair.generate()
        try savePrivateKey(generated.privateKeyHex, podcastID: podcastID)
        logger.info("Generated NIP-F4 podcast key for \(podcastID.uuidString, privacy: .public)")
        return generated
    }

    private static func account(_ podcastID: UUID) -> String {
        "podcast-privkey-\(podcastID.uuidString.lowercased())"
    }
}
