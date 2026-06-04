import CryptoKit
import Foundation

// MARK: - BlossomUploader
//
// Blossom BUD-02 upload over HTTPS. The kind:24242 authorization event MUST be
// signed by the kernel (hard rule: NO signing in Swift). The compliant path is
// a kernel sign-for-return continuation — `nmp_app_sign_event_for_return`
// returns a correlation id, the signed auth event surfaces in the
// `signed_events` snapshot projection frame, Swift base64-encodes it for the
// `Authorization: Nostr …` header and PUTs the blob. That continuation is not
// wired yet, so this uploader is DEGRADED: it throws rather than signing in
// Swift. See `docs/wiki/nmp-signing-contract.md` (blossom gap family).

protocol BlossomUploading: Sendable {
    /// Upload `data` to the Blossom server, returning the stored blob URL.
    /// The kind:24242 auth event is signed by the kernel, never in Swift.
    func upload(data: Data, contentType: String) async throws -> URL
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

    func upload(data: Data, contentType: String) async throws -> URL {
        // The blob hash + descriptor are still the inputs the kernel auth event
        // needs; computing them here documents the contract for the
        // sign-for-return continuation that will replace this throw.
        _ = Data(SHA256.hash(data: data)).hexString
        _ = contentType
        throw BlossomUploadError.serverRejected(
            "Blossom upload is temporarily unavailable (kernel auth-signing not yet wired)."
        )
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
