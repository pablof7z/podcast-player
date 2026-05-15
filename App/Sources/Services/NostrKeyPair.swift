import Foundation
import P256K

/// A Nostr key pair (secp256k1). Stores only hex bytes — the live signing key
/// is reconstructed per-operation so this type is `Sendable`.
///
/// All bech32 (nsec/npub) encoding/decoding routes through the Rust core via
/// the `nip19*` free functions. Key generation and private→public derivation
/// stay on the Swift side (P256K) because no FFI helper exposes them today.
struct NostrKeyPair: Sendable {
    let privateKeyHex: String
    let publicKeyHex: String

    /// Expected byte length of a secp256k1 private key or x-only public key.
    private static let keyByteCount = 32

    private init(privateKeyHex: String, publicKeyHex: String) {
        self.privateKeyHex = privateKeyHex
        self.publicKeyHex = publicKeyHex
    }

    // MARK: - Init

    static func generate() throws -> NostrKeyPair {
        let key = try P256K.Schnorr.PrivateKey()
        return NostrKeyPair(
            privateKeyHex: Data(key.dataRepresentation).hexString,
            publicKeyHex: Data(key.xonly.bytes).hexString
        )
    }

    /// Decode an `nsec1…` bech32 string through the Rust core, then derive
    /// the matching x-only pubkey via P256K. Throws `NostrKeyPairError.invalidPrivateKey`
    /// if Rust rejects the nsec or the resulting hex is malformed.
    init(nsec: String) throws {
        let hex: String
        do {
            hex = try nip19NsecDecode(nsec: nsec)
        } catch {
            throw NostrKeyPairError.invalidPrivateKey
        }
        try self.init(privateKeyHex: hex)
    }

    init(privateKeyHex: String) throws {
        guard let data = Data(hexString: privateKeyHex),
              data.count == NostrKeyPair.keyByteCount else {
            throw NostrKeyPairError.invalidPrivateKey
        }
        let key = try P256K.Schnorr.PrivateKey(dataRepresentation: data)
        self.privateKeyHex = privateKeyHex
        self.publicKeyHex = Data(key.xonly.bytes).hexString
    }

    // MARK: - Bech32 display

    /// Bech32-encoded private key (`nsec1…`). Computed through the Rust core's
    /// NIP-19 helper. Returns the empty string if encoding fails — both
    /// initialisers validate hex/length, so in practice that branch is dead.
    var nsec: String {
        (try? nip19NsecEncode(privkeyHex: privateKeyHex)) ?? ""
    }

    /// Bech32-encoded public key (`npub1…`). Same fallback semantics as `nsec`.
    var npub: String {
        (try? nip19NpubEncode(pubkeyHex: publicKeyHex)) ?? ""
    }
}

enum NostrKeyPairError: LocalizedError {
    case invalidPrivateKey
    var errorDescription: String? { "Invalid Nostr private key" }
}

// MARK: - Hex helpers

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hexString: String) {
        let s = hexString.lowercased()
        guard s.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        self = Data(bytes)
    }
}
