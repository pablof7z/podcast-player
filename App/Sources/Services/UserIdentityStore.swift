import Foundation
import Observation
import os.log

/// The human user's Nostr identity — entirely separate from the agent's identity.
/// Manages its own keychain slot and published key state.
///
/// Start by calling `start()` once at app launch so the store auto-loads any
/// previously saved key from the keychain.
@MainActor
@Observable
final class UserIdentityStore {
    private let logger = Logger.app("UserIdentityStore")
    private(set) var publicKeyHex: String?
    private(set) var keyPair: NostrKeyPair?
    private(set) var loginError: String?

    var hasIdentity: Bool { publicKeyHex != nil }

    // MARK: - Keychain

    private static let service = "\(Bundle.main.bundleIdentifier ?? "Podcastr").user-identity"
    private static let account = "user-private-key-hex"

    // MARK: - Lifecycle

    func start() {
        do {
            guard let hex = try KeychainStore.readString(service: Self.service, account: Self.account),
                  !hex.isEmpty else { return }
            let pair = try NostrKeyPair(privateKeyHex: hex)
            keyPair = pair
            publicKeyHex = pair.publicKeyHex
        } catch {
            logger.error("UserIdentityStore.start failed to load key: \(error, privacy: .public)")
        }
    }

    // MARK: - nsec import

    func importNsec(_ nsec: String) throws {
        loginError = nil
        let trimmed = nsec.trimmed
        do {
            let pair = try NostrKeyPair(nsec: trimmed)
            try KeychainStore.saveString(pair.privateKeyHex, service: Self.service, account: Self.account)
            keyPair = pair
            publicKeyHex = pair.publicKeyHex
        } catch {
            loginError = "Invalid nsec — check the key and try again."
            throw error
        }
    }

    // MARK: - Generate ephemeral key (auto-attribution without exposing nsec)

    func generateKey() throws {
        loginError = nil
        do {
            let pair = try NostrKeyPair.generate()
            try KeychainStore.saveString(pair.privateKeyHex, service: Self.service, account: Self.account)
            keyPair = pair
            publicKeyHex = pair.publicKeyHex
        } catch {
            loginError = "Failed to generate key — please try again."
            throw error
        }
    }

    // MARK: - Sign out

    func clearIdentity() {
        do {
            try KeychainStore.deleteString(service: Self.service, account: Self.account)
        } catch {
            logger.error("UserIdentityStore.clearIdentity failed: \(error, privacy: .public)")
        }
        keyPair = nil
        publicKeyHex = nil
    }

    // MARK: - Display helpers

    var npub: String? { keyPair?.npub }

    var npubShort: String? {
        guard let full = npub, full.count > 16 else { return npub }
        return "\(full.prefix(10))…\(full.suffix(6))"
    }
}
