import Foundation

// MARK: - UserIdentityStore nostrconnect flow
//
// Keeps nostrconnect pairing logic out of the 500-line-capped core file.
// Uses the internal seams added to the main file.

extension UserIdentityStore {

    /// Begin nostrconnect:// pairing through NDKSwift. Generates a
    /// nostrconnect URI synchronously and calls `onURI` so the UI can
    /// display the QR code or open a signer app immediately. Blocks until
    /// the bunker dials back or the underlying NDKBunkerSigner times out.
    /// On success the identity switches to `.remoteSigner`. The bunker
    /// session is not persisted — re-pair on next launch (force-re-pair).
    func connectViaNostrConnect(
        relay: URL?,
        onURI: @escaping @Sendable (String) -> Void
    ) async {
        _beginNostrConnect()
        do {
            let relay = try nostrConnectRelay(from: relay)
            let (signer, uri) = try await RemoteSigner.nostrConnect(relays: [relay])
            onURI(uri)
            let userPub = try await signer.connect()
            await _adoptNostrConnectSigner(signer: signer, userPubkeyHex: userPub)
            loadCachedProfile(for: userPub)
            let pub = userPub
            Task { await self.fetchAndCacheProfile(pubkeyHex: pub) }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            _failNostrConnect(msg)
        }
    }

    private func nostrConnectRelay(from relay: URL?) throws -> URL {
        if let relay { return relay }
        if let connected = NostrStack.shared.connectedRelayURL?.trimmed,
           let url = URL(string: connected) {
            return url
        }
        throw NostrSignerError.notConnected
    }
}
