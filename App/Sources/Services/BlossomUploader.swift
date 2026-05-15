import Foundation

// MARK: - BlossomUploader
//
// Blossom BUD-02 upload. The Rust core (`PodcastrCore`) now owns the wire
// protocol: SHA-256 hashing, kind:24242 authorization-event signing using
// the active session signer, the PUT to `/upload`, and the response parse.
// This Swift wrapper is a thin facade that picks the server URL and
// forwards bytes across the FFI boundary.
//
// One Blossom host — no abstraction layer, no fallback list. If the
// default goes down, swap `defaultServer`.

protocol BlossomUploading: Sendable {
    /// Upload `data` to the Blossom server. Returns the absolute URL the
    /// server stored the blob at.
    ///
    /// `signer` is retained for API compatibility but is **unused** post
    /// rust-cutover — the Rust core signs the BUD-02 authorization event
    /// with whichever session signer is currently active. Callers can
    /// pass any `NostrSigner`; the value is ignored. See `// rust-cutover`.
    func upload(data: Data, contentType: String, signer: any NostrSigner) async throws -> URL
}

struct BlossomUploader: BlossomUploading {

    /// Default Blossom server (blossom.primal.net per project config).
    static let defaultServer = URL(string: "https://blossom.primal.net")!

    let server: URL

    init(server: URL = BlossomUploader.defaultServer) {
        self.server = server
    }

    /// Convenience init that accepts a raw URL string from `Settings.blossomServerURL`.
    /// Falls back to `defaultServer` when the string is empty or malformed.
    init(serverURLString: String) {
        let parsed = URL(string: serverURLString.trimmed)
        self.init(server: parsed ?? BlossomUploader.defaultServer)
    }

    func upload(data: Data, contentType: String, signer: any NostrSigner) async throws -> URL {
        // rust-cutover: `signer` is intentionally ignored. The Rust core
        // builds and signs the kind:24242 auth event with the active
        // session signer; passing a different signer here has no effect.
        _ = signer

        let urlStr = try await PodcastrCoreBridge.shared.core.blossomUpload(
            data: data,
            contentType: contentType,
            serverUrl: server.absoluteString
        )
        // The Rust core already validated that the descriptor URL parses
        // before returning it, so the force-unwrap is sound. If a future
        // core version relaxes that guarantee we'll surface the failure
        // here loudly rather than silently returning a placeholder.
        return URL(string: urlStr)!
    }
}

// MARK: - Errors
//
// Retained as a public surface in case external code (tests, callers that
// haven't migrated) catches these cases. The Rust core now produces its
// own error variants which surface through the generated FFI bridge; the
// cases below are no longer thrown from `upload(…)` but the type stays so
// the API doesn't shrink under callers' feet.
// FIXME(rust-cutover): once all catch sites migrate to bridged Rust errors,
// this enum can be deleted.
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
