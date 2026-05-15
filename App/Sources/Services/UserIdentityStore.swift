@preconcurrency import Combine
import Foundation
@preconcurrency import NDKSwiftCore
import Observation
import os.log

/// The human user's Nostr identity — entirely separate from the agent's identity.
/// Manages its own keychain slot and published key state.
///
/// Two flavours of identity are supported:
/// 1. **Local nsec** — a private key stored in the iOS Keychain.
/// 2. **Remote signer (NIP-46)** — a "bunker" connection where the user's nsec lives
///    elsewhere (Amber, nsec.app, nsecBunker, …) and we delegate signing over a relay.
///
/// Call `start()` once at app launch so the store auto-loads any previously saved key.
/// Bunker sessions are **not** persisted across launches — under NDKSwift the user
/// re-pairs their bunker on each app install (one-time disruption on the migration
/// release, then standard NDKBunkerSigner sessions from there).
@MainActor
@Observable
final class UserIdentityStore {
    private let logger = Logger.app("UserIdentityStore")

    /// The user's signing pubkey (32-byte hex x-only). Always reflects whichever signer
    /// is currently active — local key or NIP-46 user pubkey.
    private(set) var publicKeyHex: String?
    /// Hex private key for the local-key path. `nil` when no local key is active
    /// (either no identity, or remote-signer mode). Surfaced for the few callers
    /// that need it for NIP-04 / NIP-44 operations outside the signer.
    private(set) var privateKeyHex: String?
    private(set) var loginError: String?

    /// What kind of identity is currently active.
    enum Mode: String, Sendable, Codable {
        case none
        case localKey
        case remoteSigner
    }
    private(set) var mode: Mode = .none

    /// The active signer. Whatever the rest of the app uses to sign events.
    /// `nil` while no identity is configured.
    private(set) var signer: (any NostrSigner)?

    /// Live state of the NIP-46 connection (UI surfaces this).
    private(set) var remoteSignerState: RemoteSignerState = .idle

    /// Cached kind:0 profile fields fetched from relays. `nil` until the
    /// first fetch completes; populated immediately on launch from the
    /// UserDefaults cache so the UI never flashes generated → real.
    var profileDisplayName: String?
    var profileName: String?
    var profileAbout: String?
    var profilePicture: String?

    var hasIdentity: Bool { publicKeyHex != nil }
    var isRemoteSigner: Bool { mode == .remoteSigner }

    // MARK: - Keychain slots

    private static let userKeyService = "\(Bundle.main.bundleIdentifier ?? "Podcastr").user-identity"
    private static let userKeyAccount = "user-private-key-hex"
    private static let userKeyOriginAccount = "user-private-key-origin"
    private static let generatedProfileAccount = "generated-profile-published-pubkey"
    /// Legacy NIP-46 keychain entries from the pre-NDKSwift signer. We delete
    /// these on first launch under NDKSwift; users re-pair their bunker.
    private static let legacyNip46SessionService = "\(Bundle.main.bundleIdentifier ?? "Podcastr").nip46-session"
    private static let legacyNip46SessionAccount = "session-private-key-hex"
    private static let legacyNip46MetaService = "\(Bundle.main.bundleIdentifier ?? "Podcastr").nip46-meta"
    private static let legacyNip46MetaAccount = "connection"
    private static let generatedOrigin = "generated"

    // MARK: - Lifecycle

    func start() {
        purgeLegacyNip46KeychainEntries()
        // Prefer an existing local key.
        do {
            if let hex = try KeychainStore.readString(service: Self.userKeyService, account: Self.userKeyAccount),
               !hex.isEmpty {
                try adoptLocal(privateKeyHex: hex)
                if isGeneratedLocalKey {
                    publishGeneratedProfileIfNeeded(privateKeyHex: hex)
                }
                return
            }
        } catch {
            logger.error("UserIdentityStore.start failed to load local key: \(error, privacy: .public)")
        }
        // Force-re-pair migration: no resume of NIP-46 sessions; user re-pairs.
        do {
            try generateGeneratedKey()
        } catch {
            logger.error("UserIdentityStore.start failed to generate local key: \(error, privacy: .public)")
        }
    }

    // MARK: - nsec import

    func importNsec(_ nsec: String) throws {
        loginError = nil
        let trimmed = nsec.trimmed
        do {
            let parsed = try NDKPrivateKeySigner(nsec: trimmed)
            let privHex = parsed.privateKeyForNIP59
            try KeychainStore.saveString(privHex, service: Self.userKeyService, account: Self.userKeyAccount)
            try? KeychainStore.deleteString(service: Self.userKeyService, account: Self.userKeyOriginAccount)
            clearRemoteConnectionState()
            try adoptLocal(privateKeyHex: privHex)
        } catch {
            loginError = "Invalid nsec — check the key and try again."
            throw error
        }
    }

    // MARK: - Generate ephemeral key

    func generateKey() throws {
        loginError = nil
        do {
            let privHex = try NDKPrivateKeySigner.generate().privateKeyForNIP59
            try KeychainStore.saveString(privHex, service: Self.userKeyService, account: Self.userKeyAccount)
            try KeychainStore.saveString(Self.generatedOrigin, service: Self.userKeyService, account: Self.userKeyOriginAccount)
            clearRemoteConnectionState()
            try adoptLocal(privateKeyHex: privHex)
            publishGeneratedProfileIfNeeded(privateKeyHex: privHex)
        } catch {
            loginError = "Failed to generate key — please try again."
            throw error
        }
    }

    // MARK: - Sign out

    func clearIdentity() {
        do {
            try KeychainStore.deleteString(service: Self.userKeyService, account: Self.userKeyAccount)
        } catch {
            logger.error("UserIdentityStore.clearIdentity failed: \(error, privacy: .public)")
        }
        try? KeychainStore.deleteString(service: Self.userKeyService, account: Self.userKeyOriginAccount)
        try? KeychainStore.deleteString(service: Self.userKeyService, account: Self.generatedProfileAccount)
        Task { await self.tearDownRemote() }
        privateKeyHex = nil
        publicKeyHex = nil
        signer = nil
        mode = .none
        remoteSignerState = .idle
        profileDisplayName = nil
        profileName = nil
        profileAbout = nil
        profilePicture = nil
    }

    // MARK: - NIP-46 connect / disconnect

    /// Pair with a `bunker://…` URI through NDKSwift's `NDKBunkerSigner`.
    /// On success, the bunker connection is held in memory for the session;
    /// it is **not** persisted to Keychain (force-re-pair model).
    func connectRemoteSigner(uri: String) async {
        loginError = nil
        remoteSignerState = .connecting
        do {
            let trimmed = uri.trimmed
            let signer = try await RemoteSigner.bunker(uri: trimmed)
            await wireAuthChallengeBridge(on: signer)
            let userPub = try await signer.connect()
            try? KeychainStore.deleteString(service: Self.userKeyService, account: Self.userKeyAccount)
            try? KeychainStore.deleteString(service: Self.userKeyService, account: Self.userKeyOriginAccount)
            self.signer = signer
            self.publicKeyHex = userPub
            self.privateKeyHex = nil
            self.mode = .remoteSigner
            self.remoteSignerState = .connected(userPub)
            self.loadCachedProfile(for: userPub)
            let pub = userPub
            Task { await self.fetchAndCacheProfile(pubkeyHex: pub) }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            loginError = msg
            remoteSignerState = .failed(msg)
        }
    }

    /// Subscribes to the bunker's `auth_url` publisher and routes URLs to
    /// `remoteSignerState` so the UI can surface a "Tap to authorize" button.
    private func wireAuthChallengeBridge(on signer: RemoteSigner) async {
        let publisher = signer.authUrlPublisher
        publisher.sink { [weak self] url in
            Task { @MainActor in
                self?.remoteSignerState = .awaitingAuthorization(url)
            }
        }.store(in: &authChallengeBag)
    }

    private var authChallengeBag: Set<AnyCancellable> = []

    func disconnectRemoteSigner() async {
        await tearDownRemote()
        publicKeyHex = nil
        privateKeyHex = nil
        signer = nil
        mode = .none
        remoteSignerState = .idle
        authChallengeBag.removeAll()
    }

    // MARK: - Display helpers

    var npub: String? {
        guard let hex = publicKeyHex, let bytes = Data(hexString: hex), bytes.count == 32 else { return nil }
        return Bech32.encode(hrp: "npub", data: bytes)
    }

    var npubShort: String? {
        guard let full = npub, full.count > 16 else { return npub }
        return "\(full.prefix(10))…\(full.suffix(6))"
    }

    // MARK: - Private — local

    private func adoptLocal(privateKeyHex hex: String) throws {
        let pubHex = try Crypto.getPublicKey(from: hex)
        let localSigner = try LocalKeySigner(privateKeyHex: hex)
        self.privateKeyHex = hex
        self.publicKeyHex = pubHex
        self.signer = localSigner
        mode = .localKey
        remoteSignerState = .idle
        loadCachedProfile(for: pubHex)
        guard !isGeneratedLocalKey else { return }
        Task { await self.fetchAndCacheProfile(pubkeyHex: pubHex) }
    }

    private var isGeneratedLocalKey: Bool {
        (try? KeychainStore.readString(
            service: Self.userKeyService,
            account: Self.userKeyOriginAccount
        )) == Self.generatedOrigin
    }

    private func generateGeneratedKey() throws {
        let privHex = try NDKPrivateKeySigner.generate().privateKeyForNIP59
        try KeychainStore.saveString(privHex, service: Self.userKeyService, account: Self.userKeyAccount)
        try KeychainStore.saveString(Self.generatedOrigin, service: Self.userKeyService, account: Self.userKeyOriginAccount)
        try adoptLocal(privateKeyHex: privHex)
        publishGeneratedProfileIfNeeded(privateKeyHex: privHex)
    }

    private func clearRemoteConnectionState() {
        if let remote = signer as? RemoteSigner {
            Task { await remote.disconnect() }
        }
        remoteSignerState = .idle
    }

    private func publishGeneratedProfileIfNeeded(privateKeyHex: String) {
        let alreadyPublished = try? KeychainStore.readString(
            service: Self.userKeyService,
            account: Self.generatedProfileAccount
        )
        guard let pubkey = try? Crypto.getPublicKey(from: privateKeyHex),
              alreadyPublished != pubkey else { return }
        let keyService = Self.userKeyService
        let profileAccount = Self.generatedProfileAccount
        guard let signer = try? LocalKeySigner(privateKeyHex: privateKeyHex) else { return }
        let profile = Self.generatedProfile(pubkey: pubkey)
        Task.detached {
            guard let data = try? JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys]),
                  let content = String(data: data, encoding: .utf8) else { return }
            let event = try await signer.sign(NostrEventDraft(kind: 0, content: content))
            var published = false
            for relayURL in FeedbackRelayClient.profileRelayURLs {
                let client = FeedbackRelayClient(relayURL: relayURL)
                do {
                    try await client.publish(event, authSigner: signer)
                    published = true
                } catch {
                    continue
                }
            }
            if published {
                try? KeychainStore.saveString(
                    pubkey,
                    service: keyService,
                    account: profileAccount
                )
            }
        }
    }

    private static func generatedProfile(pubkey: String) -> [String: String] {
        let seed = String(pubkey.prefix(16))
        let index = stableProfileIndex(seed)
        let adjectives = ["Bright", "Quiet", "Swift", "Kind", "Clear", "North"]
        let nouns = ["Signal", "Notebook", "Harbor", "Lantern", "Thread", "Field"]
        let adjective = adjectives[index % adjectives.count]
        let noun = nouns[(index / adjectives.count) % nouns.count]
        return [
            "name": "\(adjective.lowercased())-\(noun.lowercased())-\(pubkey.prefix(4))",
            "display_name": "\(adjective) \(noun)",
            "about": "Feedback identity generated by Podcastr.",
            "picture": "https://api.dicebear.com/9.x/personas/svg?seed=\(seed)",
        ]
    }

    private static func stableProfileIndex(_ seed: String) -> Int {
        seed.utf8.reduce(0) { partial, byte in
            (partial &* 31 &+ Int(byte)) & 0x7fffffff
        }
    }

    // MARK: - Legacy NIP-46 keychain purge (one-time on upgrade)

    /// Wipes pre-NDKSwift bunker session entries from the Keychain so the
    /// app starts in a clean state on the migration release. Users re-pair
    /// their bunker after upgrading. Safe to run on every launch; idempotent.
    private func purgeLegacyNip46KeychainEntries() {
        try? KeychainStore.deleteString(service: Self.legacyNip46SessionService, account: Self.legacyNip46SessionAccount)
        try? KeychainStore.deleteString(service: Self.legacyNip46MetaService, account: Self.legacyNip46MetaAccount)
    }

    // MARK: - Private — remote

    private func tearDownRemote() async {
        if let s = signer as? RemoteSigner { await s.disconnect() }
    }

    // MARK: - Process-wide singleton (slice B)

    /// Process-wide instance used by the wiring layer (`AppStateStore+Notes`,
    /// `AppStateStore+Clips`, `EditProfileView.save`) so domain-level
    /// extensions can publish without DI threading. The SwiftUI environment
    /// instance in `AppMain` references the same object so observation stays
    /// consistent.
    static let shared = UserIdentityStore()

    // MARK: - Slice-B internal helpers

    /// Internal alias for the file-private `generateGeneratedKey()` so the
    /// extension file `UserIdentityStore+Publishing.swift` can self-heal
    /// when invoked without an active signer.
    func _ensureGeneratedKey() throws {
        try generateGeneratedKey()
    }

    func _beginNostrConnect() {
        loginError = nil
        remoteSignerState = .connecting
    }

    func _failNostrConnect(_ message: String) {
        loginError = message
        remoteSignerState = .failed(message)
    }

    /// Called by `UserIdentityStore+NIP46.swift` after nostrconnect pairing completes.
    /// Updates published identity state. Bunker session is not persisted
    /// (force-re-pair model).
    func _adoptNostrConnectSigner(signer: RemoteSigner, userPubkeyHex: String) async {
        await wireAuthChallengeBridge(on: signer)
        try? KeychainStore.deleteString(service: Self.userKeyService, account: Self.userKeyAccount)
        try? KeychainStore.deleteString(service: Self.userKeyService, account: Self.userKeyOriginAccount)
        self.signer = signer
        self.publicKeyHex = userPubkeyHex
        self.privateKeyHex = nil
        self.mode = .remoteSigner
        self.remoteSignerState = .connected(userPubkeyHex)
    }

    // MARK: - Test seam (slice B)

    /// Test-only: swap in a recording signer so wiring tests can verify
    /// which call-sites reach the signer without standing up a real keypair.
    /// Production code never calls this. Lives in the core file because
    /// `signer` / `publicKeyHex` / `mode` use file-private `private(set)`.
    func _setSignerForTesting(_ signer: any NostrSigner, publicKeyHex: String = String(repeating: "0", count: 64)) {
        self.signer = signer
        self.publicKeyHex = publicKeyHex
        self.mode = .localKey
    }

    /// Test-only: drop the active signer so tests can verify the
    /// `signer == nil` → `generateGeneratedKey()` self-heal path.
    func _clearSignerForTesting() {
        self.signer = nil
        self.publicKeyHex = nil
        self.mode = .none
    }
}

// MARK: - Supporting types

/// Connection state surfaced to the UI for the NIP-46 flow.
enum RemoteSignerState: Sendable, Equatable {
    case idle
    case connecting
    case reconnecting
    /// The bunker replied with an `auth_url` challenge — the user must approve in a
    /// browser. The connect call itself is still suspended; `connected(...)` follows
    /// once the bunker delivers the real `ack`.
    case awaitingAuthorization(URL)
    case connected(String)            // associated value: user pubkey hex
    case failed(String)               // error message
}

enum UserIdentityError: LocalizedError {
    case noIdentity

    var errorDescription: String? {
        switch self {
        case .noIdentity:
            "No feedback identity is available."
        }
    }
}
