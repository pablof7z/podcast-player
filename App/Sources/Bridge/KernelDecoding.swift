import Foundation

/// Canonical decoder configuration for everything the kernel emits over the FFI
/// bridge. The Rust side serializes with serde's default (snake_case) field
/// names, so every bridge decode site uses `.convertFromSnakeCase`.
///
/// Centralized as the single source of truth so the wire-contract test
/// (`PlatformWidgetContractTests`) exercises the *exact* config the production
/// decode path uses — not a hand-copied duplicate that could silently drift.
/// This is the seam that pins Rust-JSON ↔ Swift-mirror compatibility; the
/// embedded `WidgetSnapshot` regression (PR #366) slipped through precisely
/// because no test ran kernel JSON through this configuration. The embedded
/// `WidgetSnapshot` (and every other type reached via `PodcastUpdate`) must
/// therefore have NO explicit snake_case `CodingKeys`: under this strategy that
/// double-converts and makes required keys throw `keyNotFound`, failing the
/// whole frame.
enum KernelDecoding {
    /// A fresh `JSONDecoder` configured the way the bridge decodes kernel JSON.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Decode a `PodcastUpdate` from the raw `podcast.snapshot` projection bytes
    /// using the canonical bridge config. Throws on malformed JSON at the type
    /// level — callers map the error to their own logging.
    static func decodePodcastUpdate(from data: Data) throws -> PodcastUpdate {
        try makeDecoder().decode(PodcastUpdate.self, from: data)
    }
}
