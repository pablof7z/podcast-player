@preconcurrency import Combine
import Foundation
@preconcurrency import NDKSwiftCore
import os.log

/// `NostrSigner` backed by a NIP-46 remote signer ("bunker"). Internally
/// wraps `NDKBunkerSigner` from NDKSwift, which owns the kind:24133
/// encrypted RPC channel, NIP-44 envelope, relay walking, and `auth_url`
/// surfacing. This shim exposes the small slice of behavior the rest of
/// the app uses.
///
/// Reactive: the bunker's `auth_url` is republished via Combine on
/// `authUrlPublisher` so identity UI binds to the publisher directly
/// rather than polling for state.
actor RemoteSigner: NostrSigner {
    nonisolated private static let logger = Logger.app("RemoteSigner")

    private let bunkerSigner: NDKBunkerSigner
    /// Forwards `auth_url` events from `NDKBunkerSigner.authUrlPublisher`
    /// out to UI without forcing UI code to take a transitive dependency
    /// on `Combine` + `NDKSwiftCore`.
    nonisolated let authUrlPublisher = PassthroughSubject<URL, Never>()
    private var authUrlBridge: AnyCancellable?

    private init(bunkerSigner: NDKBunkerSigner) async {
        self.bunkerSigner = bunkerSigner
        await wireAuthUrlBridge()
    }

    // MARK: - Factories

    /// Construct a signer for a `bunker://` URI. Does not connect — call
    /// `connect()` to perform the handshake.
    static func bunker(uri: String) async throws -> RemoteSigner {
        guard let ndk = await NostrStack.shared.ndk else {
            throw NostrSignerError.notConnected
        }
        let bunker = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: uri)
        return await RemoteSigner(bunkerSigner: bunker)
    }

    /// Construct a signer using the `nostrconnect://` flow (the app
    /// publishes a URI, the user pastes it into their bunker). The URI
    /// is read off the returned tuple's second slot.
    static func nostrConnect(
        relays: [URL],
        appName: String? = nil,
        appURL: String? = nil,
        appImage: String? = nil,
        permissions: String? = nil
    ) async throws -> (RemoteSigner, String) {
        guard let ndk = await NostrStack.shared.ndk else {
            throw NostrSignerError.notConnected
        }
        let options = NDKBunkerSigner.NostrConnectOptions(
            name: appName,
            url: appURL,
            image: appImage,
            perms: permissions
        )
        let bunker = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: relays.map { $0.absoluteString },
            options: options
        )
        let signer = await RemoteSigner(bunkerSigner: bunker)
        let uri = await bunker.nostrConnectUri ?? ""
        return (signer, uri)
    }

    // MARK: - Lifecycle

    /// Perform the bunker handshake. Returns the user's pubkey on success.
    /// Throws on failure / timeout. UI should observe `authUrlPublisher`
    /// in parallel so an `auth_url` surfaced mid-handshake reaches the
    /// presentation layer reactively.
    @discardableResult
    func connect() async throws -> String {
        do {
            return try await bunkerSigner.connect()
        } catch {
            Self.logger.warning("connect: handshake failed — \(error, privacy: .public)")
            throw error
        }
    }

    /// Tear down the underlying bunker connection. Idempotent.
    func disconnect() async {
        await bunkerSigner.disconnect()
        authUrlBridge?.cancel()
        authUrlBridge = nil
    }

    // MARK: - NostrSigner

    func publicKey() async throws -> String {
        try await bunkerSigner.getPublicKey()
    }

    func sign(_ draft: NostrEventDraft) async throws -> SignedNostrEvent {
        try await NostrSignerShim.signDraft(draft, with: bunkerSigner)
    }

    // MARK: - Auth URL bridge

    private func wireAuthUrlBridge() async {
        let outbound = authUrlPublisher
        let upstream = await bunkerSigner.authUrlPublisher
        authUrlBridge = upstream
            .compactMap { URL(string: $0) }
            .sink { url in outbound.send(url) }
    }
}
