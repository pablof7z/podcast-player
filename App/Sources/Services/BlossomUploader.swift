import CryptoKit
import Foundation

// MARK: - BlossomUploader
//
// Blossom BUD-02 upload over HTTPS. Hashes the payload, signs a kind:24242
// authorization event, PUTs `/upload`, and returns the descriptor URL the
// server hands back. One Blossom host — no abstraction layer, no fallback
// list. If the default goes down, swap `defaultServer`.

protocol BlossomUploading: Sendable {
    /// Upload `data` to the Blossom server. Returns the absolute URL the
    /// server stored the blob at. `signer` produces the kind:24242 auth event.
    ///
    /// LEGACY (raw-key) path — kept only for the agent flow during migration.
    /// New callers use `upload(data:contentType:accountPubkey:kernel:)`, which
    /// signs through the kernel (D13 — no raw private key bytes, NIP-46 safe).
    func upload(data: Data, contentType: String, signer: any NostrSigner) async throws -> URL

    /// Upload `data`, signing the kind:24242 Blossom auth event through the
    /// KERNEL (D13). `accountPubkey` is the hex pubkey of the signer to use
    /// (pass `""` for the active account). No raw private key bytes cross the
    /// FFI boundary — this works for NIP-46 bunker users, which the `signer:`
    /// overload could not.
    func upload(
        data: Data, contentType: String, accountPubkey: String, kernel: KernelModel
    ) async throws -> URL
}

struct BlossomUploader: BlossomUploading {

    /// Default Blossom server (blossom.primal.net per project config).
    static let defaultServer = URL(string: "https://blossom.primal.net")!

    let server: URL
    let session: URLSession

    init(server: URL = BlossomUploader.defaultServer, session: URLSession = .shared) {
        self.server = server
        self.session = session
    }

    /// Convenience init that accepts a raw URL string from `Settings.blossomServerURL`.
    /// Falls back to `defaultServer` when the string is empty or malformed.
    init(serverURLString: String, session: URLSession = .shared) {
        let parsed = URL(string: serverURLString.trimmed)
        self.init(server: parsed ?? BlossomUploader.defaultServer, session: session)
    }

    func upload(data: Data, contentType: String, signer: any NostrSigner) async throws -> URL {
        let hashHex = Data(SHA256.hash(data: data)).hexString
        let now = Int(Date().timeIntervalSince1970)
        let description = Self.description(for: contentType)
        let draft = NostrEventDraft(
            kind: 24242,
            content: description,
            tags: [
                ["t", "upload"],
                ["x", hashHex],
                ["expiration", String(now + 60 * 5)],
            ],
            createdAt: now
        )
        let signed = try await signer.sign(draft)
        let authJSON = try JSONSerialization.data(withJSONObject: eventDictionary(signed), options: [])
        let authB64 = authJSON.base64EncodedString()
        return try await put(data: data, contentType: contentType, authB64: authB64)
    }

    /// D13 kernel-signed upload. Builds the kind:24242 auth event draft, signs
    /// it through the kernel (`KernelModel.signEventForReturn`), and PUTs the
    /// blob with the signed event as the `Authorization: Nostr <base64>` header.
    func upload(
        data: Data, contentType: String, accountPubkey: String, kernel: KernelModel
    ) async throws -> URL {
        let hashHex = Data(SHA256.hash(data: data)).hexString
        let now = Int(Date().timeIntervalSince1970)
        let description = Self.description(for: contentType)
        // `created_at` is advisory — the kernel re-stamps it (D7). Sent so the
        // draft shape is uniform with the `expiration` tag math below.
        let draftObject: [String: Any] = [
            "kind": 24242,
            "content": description,
            "tags": [
                ["t", "upload"],
                ["x", hashHex],
                ["expiration", String(now + 60 * 5)],
            ],
            "created_at": now,
        ]
        let unsignedJSON = try Self.json(from: draftObject)
        let signedJSON = try await kernel.signEventForReturn(
            accountPubkeyHex: accountPubkey,
            unsignedJSON: unsignedJSON
        )
        // The kernel returns the flat NIP-01 event JSON ready to base64.
        guard let authData = signedJSON.data(using: .utf8) else {
            throw BlossomUploadError.invalidResponse
        }
        let authB64 = authData.base64EncodedString()
        return try await put(data: data, contentType: contentType, authB64: authB64)
    }

    /// Human-readable `content` string for the kind:24242 auth event, by MIME.
    private static func description(for contentType: String) -> String {
        switch contentType {
        case "audio/mpeg", "audio/mp4", "audio/m4a": return "Upload podcast audio"
        case "application/json":                      return "Upload podcast data"
        case "text/vtt", "text/plain":                return "Upload transcript"
        case "image/jpeg", "image/png", "image/webp": return "Upload podcast artwork"
        default:                                      return "Upload file"
        }
    }

    private static func json(from object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw BlossomUploadError.invalidResponse
        }
        return json
    }

    /// Shared HTTP PUT for both the legacy (raw-key) and kernel-signed paths.
    /// `authB64` is the base64-encoded signed kind:24242 auth event.
    private func put(data: Data, contentType: String, authB64: String) async throws -> URL {
        var request = URLRequest(url: server.appendingPathComponent("upload"))
        request.httpMethod = "PUT"
        request.setValue("Nostr \(authB64)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BlossomUploadError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            // Blossom servers convey rejection details in the `X-Reason` header
            // per BUD-01 §4. Fall back to the body if absent.
            let reason = http.value(forHTTPHeaderField: "X-Reason")
                ?? String(data: responseData, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
                ?? "HTTP \(http.statusCode)"
            throw BlossomUploadError.serverRejected(reason)
        }
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let urlString = object["url"] as? String,
              let url = URL(string: urlString) else {
            throw BlossomUploadError.malformedDescriptor
        }
        return url
    }

    private func eventDictionary(_ event: SignedNostrEvent) -> [String: Any] {
        [
            "id": event.id,
            "pubkey": event.pubkey,
            "created_at": event.created_at,
            "kind": event.kind,
            "tags": event.tags,
            "content": event.content,
            "sig": event.sig,
        ]
    }
}

enum BlossomUploadError: LocalizedError {
    case invalidResponse
    case serverRejected(String)
    case malformedDescriptor

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Upload server did not respond."
        case .serverRejected(let reason): return "Upload rejected: \(reason)"
        case .malformedDescriptor: return "Upload server returned a malformed response."
        }
    }
}
