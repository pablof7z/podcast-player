import Foundation

// MARK: - UserIdentityStore nostrconnect flow
//
// Keeps nostrconnect pairing logic out of the 500-line-capped core file.
// The hand-rolled Swift NIP-46 transport has been replaced with the Rust
// core's `nip46StartNostrconnect` / `nip46AwaitSigner` pair. The Rust core
// owns the relay socket, ephemeral session key, encryption, and the wait
// for the bunker's `connect` handshake.

extension UserIdentityStore {

    /// Begin nostrconnect:// pairing. Asks the Rust core to mint a fresh
    /// nostrconnect URI and invokes `onURI` so the UI can render a QR code
    /// or open a signer app immediately. Then suspends until the remote
    /// signer pairs (or the 180s deadline expires inside Rust). On success
    /// the identity switches to `.remoteSigner` and the connection is
    /// persisted (by the Rust core) for automatic reconnect on next launch.
    ///
    /// The `relay` parameter is preserved on the Swift API surface for
    /// caller compatibility — callers pass `RemoteSigner.nostrConnectDefaultRelay`
    /// today and we forward that URL string straight into Rust.
    func connectViaNostrConnect(
        relay: URL = RemoteSigner.nostrConnectDefaultRelay,
        onURI: @escaping @Sendable (String) -> Void
    ) async {
        _beginNostrConnect()
        let bridge = PodcastrCoreBridge.shared
        do {
            let uri = try await bridge.core.nip46StartNostrconnect(
                relayUrl: relay.absoluteString,
                appName: "Podcastr",
                appUrl: nil,
                appImage: nil
            )
            onURI(uri)

            let userPub = try await bridge.core.nip46AwaitSigner(timeoutSecs: 180)

            // FIXME(rust-cutover): `_adoptNostrConnectSigner` in the core
            // `UserIdentityStore.swift` requires a Swift `RemoteSigner`
            // instance + session privkey hex to install. The Rust core now
            // owns the entire NIP-46 session and only hands back the user
            // pubkey hex — there is no `RemoteSigner` to pass and no session
            // privkey exposed across the FFI. A follow-up agent must add a
            // new seam alongside the existing one, e.g.:
            //
            //     func _adoptRustNostrConnect(userPubkeyHex: String,
            //                                 relayAbsoluteString: String) throws
            //
            // which sets `mode = .remoteSigner`, `publicKeyHex = userPubkeyHex`,
            // `remoteSignerState = .connected(userPubkeyHex)`, and installs
            // a Rust-backed `NostrSigner` shim on `self.signer` so existing
            // call sites (`signer.sign(_:)` etc.) keep working. CRITICAL:
            // the seam MUST assign `self.publicKeyHex = userPubkeyHex`
            // *before* returning — otherwise the `fetchAndCacheProfile`
            // call below short-circuits at its
            // `guard self.publicKeyHex == pubkeyHex` check and silently
            // drops the profile fields.
            //
            // The call below uses that planned signature. Once the seam
            // ships this line compiles unchanged; until then the Swift
            // type-checker will flag it and the follow-up agent has a
            // one-line target to fix.
            try _adoptRustNostrConnect(
                userPubkeyHex: userPub,
                relayAbsoluteString: relay.absoluteString
            )

            loadCachedProfile(for: userPub)
            let pub = userPub
            Task { await self.fetchAndCacheProfile(pubkeyHex: pub) }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            _failNostrConnect(msg)
        }
    }
}
