import Foundation

/// Compatibility facade for existing Swift call sites. Rust owns the actual
/// feed URL normalization policy through `nmp_app_podcast_normalize_feed_url`.
enum FeedURLNormalizer {
    private struct Response: Decodable {
        let url: String?
        let error: String?
    }

    static func normalizedFeedURL(from input: String) -> URL? {
        let envelope = {
            guard let result = podcastAppGlobalString(endpoint: .normalizeFeedUrl, request: input) else {
                return nil
            }
            return result
        }()
        guard let envelope,
              let data = envelope.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.error == nil,
              let rawURL = response.url
        else { return nil }
        return URL(string: rawURL)
    }
}
