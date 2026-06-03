import Foundation

// MARK: - UserIdentityStore nostrconnect flow
//
// Routes all NIP-46 pairing through the NMP kernel — no Swift WebSocket,
// no Nip44 crypto, no RemoteSigner in this path.
//
// * `connectViaNostrConnect`: kernel generates the URI AND starts listening;
//   UI observes `remoteSignerState` reactively via `applyBunkerHandshake`.
// * `applyBunkerHandshake`: called by `AppStateStore` on every kernel identity
//   snapshot tick; maps `KernelBunkerHandshake` → `remoteSignerState`.

extension UserIdentityStore {

    /// Begin nostrconnect:// pairing via the kernel's NIP-46 broker.
    /// The kernel generates the URI and immediately starts listening for the
    /// signer app's response on its embedded relay — no Swift WebSocket.
    /// State changes arrive via `applyBunkerHandshake` on the next snapshot tick.
    func connectViaNostrConnect(
        relay: URL? = nil,
        onURI: @escaping @Sendable (String) -> Void
    ) async {
        _beginNostrConnect()
        guard let uri = kernel?.nostrconnectURI(
            relayURL: relay?.absoluteString,
            callbackScheme: "podcastr"
        ) else {
            _failNostrConnect("Kernel unavailable")
            return
        }
        onURI(uri)
        // State progression (connecting → connected/failed) comes reactively
        // via AppStateStore.applyBunkerHandshake on kernel snapshot ticks.
    }

    /// Called by AppStateStore on every kernel identity snapshot tick.
    /// Maps the kernel's `KernelBunkerHandshake` projection to `remoteSignerState`.
    @MainActor
    func applyBunkerHandshake(_ handshake: KernelBunkerHandshake?, activeAccount: String?) {
        if let handshake {
            if handshake.isTerminalSuccess, let pubkey = activeAccount {
                guard case .connected = remoteSignerState else {
                    remoteSignerState = .connected(pubkey)
                    publicKeyHex = pubkey
                    mode = .remoteSigner
                    loadCachedProfile(for: pubkey)
                    Task { await self.fetchAndCacheProfile(pubkeyHex: pubkey) }
                    return
                }
            } else if handshake.isFailed {
                let msg = handshake.message ?? "NIP-46 pairing failed."
                _failNostrConnect(msg)
            }
            // isInFlight → stay in .connecting (set by _beginNostrConnect)
        }
    }
}
