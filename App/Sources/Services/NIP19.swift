import Foundation

// MARK: - NIP-19 naddr encoder
//
// Thin Swift facade around the Rust core's `nip19Naddr` free function.
// The hand-rolled TLV + bech32 encoder previously living here is gone —
// Rust owns the single source of truth so encoder/decoder stay in lockstep
// across the FFI boundary.

enum NIP19 {
    /// Encode a parameterised replaceable event as an `naddr` bech32 string.
    ///
    /// - Parameters:
    ///   - dTag: Full d-tag string, e.g. `"podcast:guid:<uuid-lowercase>"`.
    ///   - pubkeyHex: 64-character lowercase hex x-only pubkey.
    ///   - kind: Nostr event kind (e.g. 30074 or 30075).
    ///   - relayURL: Optional relay hint included as TLV type-1.
    /// - Returns: `nil` when the Rust encoder rejects the inputs (e.g.
    ///   non-hex pubkey, wrong length, malformed relay hint).
    static func naddr(
        dTag: String,
        pubkeyHex: String,
        kind: UInt32,
        relayURL: String? = nil
    ) -> String? {
        try? nip19Naddr(dTag: dTag, pubkeyHex: pubkeyHex, kind: kind, relayUrl: relayURL)
    }
}
