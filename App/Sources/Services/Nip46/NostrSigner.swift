import Foundation
@preconcurrency import NDKSwiftCore

// MARK: - Event types
//
// `NostrEventDraft` and `SignedNostrEvent` are the in-app adapter surface
// over NDKSwift's `NDKEvent`. Callers continue to construct drafts and
// receive signed events as Codable value types; the signer implementations
// delegate the actual canonicalization + signing to NDKSwift.

/// Unsigned event draft as accepted by `NostrSigner.sign(_:)`.
/// Mirrors the NIP-01 event JSON minus `id` / `pubkey` / `sig` (the signer fills those).
struct NostrEventDraft: Sendable, Equatable {
    var kind: Int
    var content: String
    var tags: [[String]]
    /// `created_at` UNIX seconds. Defaults to "now" at construction.
    var createdAt: Int

    init(kind: Int, content: String, tags: [[String]] = [], createdAt: Int = Int(Date().timeIntervalSince1970)) {
        self.kind = kind
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
    }
}

/// Fully-signed Nostr event ready to publish.
struct SignedNostrEvent: Sendable, Equatable, Codable {
    let id: String        // 32-byte hex SHA-256 of the canonical [0, pubkey, created_at, kind, tags, content].
    let pubkey: String    // 32-byte hex x-only pubkey.
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String       // 64-byte hex Schnorr signature.
}

// MARK: - Signer protocol

/// Anything that can produce a Nostr signature. Lets the rest of the app stay agnostic
/// of whether the user is signing locally (`LocalKeySigner`) or via a remote bunker
/// over NIP-46 (`RemoteSigner`). Both implementations delegate to NDKSwift's
/// `NDKSigner` family internally.
protocol NostrSigner: Sendable {
    /// The user-facing pubkey this signer publishes events under (32-byte hex x-only).
    func publicKey() async throws -> String
    /// Compute the canonical event id, sign it, and return the wire-ready event.
    func sign(_ draft: NostrEventDraft) async throws -> SignedNostrEvent
}

// MARK: - Local-key signer (NDKPrivateKeySigner-backed)

/// `NostrSigner` backed by an in-process secp256k1 key pair. Internally wraps
/// `NDKPrivateKeySigner`; event canonicalization + signing happens through
/// NDKSwift, so the app no longer carries hand-rolled BIP-340 or NIP-01 code.
struct LocalKeySigner: NostrSigner {
    let ndkSigner: NDKPrivateKeySigner

    init(privateKeyHex: String) throws {
        self.ndkSigner = try NDKPrivateKeySigner(privateKey: privateKeyHex)
    }

    func publicKey() async throws -> String {
        try await ndkSigner.pubkey
    }

    func sign(_ draft: NostrEventDraft) async throws -> SignedNostrEvent {
        try await NostrSignerShim.signDraft(draft, with: ndkSigner)
    }
}

// MARK: - Shared draft→signed adapter

/// Bridges our `NostrEventDraft` value type to NDKSwift's `NDKEventBuilder`
/// pipeline. Both `LocalKeySigner` and the NIP-46-backed `RemoteSigner` go
/// through this so the canonical-id + signature path is owned by NDKSwift.
enum NostrSignerShim {
    static func signDraft(_ draft: NostrEventDraft, with signer: NDKSigner) async throws -> SignedNostrEvent {
        // NDK must be constructed (signer-ready) — relay connection state
        // is orthogonal. `NostrStack.shared.bind(store:)` resolves this at
        // app launch before any signer call site fires.
        guard let ndk = await NostrStack.shared.ndk else {
            throw NostrSignerError.invalidEventForSigning
        }
        let builder = NDKEventBuilder(ndk: ndk)
            .kind(draft.kind)
            .content(draft.content, extractImeta: false)
            .createdAt(Timestamp(draft.createdAt))
            .setTags(draft.tags)
        let event = try await builder.build(signer: signer, generateContentTags: false)
        return SignedNostrEvent(
            id: event.id,
            pubkey: event.pubkey,
            created_at: Int(event.createdAt),
            kind: event.kind,
            tags: event.tags,
            content: event.content,
            sig: event.sig
        )
    }
}

// MARK: - Errors

enum NostrSignerError: LocalizedError {
    case invalidEventForSigning
    case remoteRejected(String)
    case timedOut
    case notConnected
    case missingPublicKey

    var errorDescription: String? {
        switch self {
        case .invalidEventForSigning: "Could not sign — event payload is invalid."
        case .remoteRejected(let m): "Remote signer rejected the request: \(m)"
        case .timedOut: "Remote signer did not respond in time."
        case .notConnected: "Remote signer is not connected."
        case .missingPublicKey: "Remote signer has not advertised a public key yet."
        }
    }
}
