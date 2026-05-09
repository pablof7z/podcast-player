import Foundation

/// Thin client over Apple's free iTunes Search API for podcast discovery.
///
/// No auth, no rate-limit headers in practice for an end-user device. We
/// use the public `entity=podcast` search; the response gives us everything
/// we need to render a result row (artwork URL, title, author, genre,
/// episode count) plus the canonical feed URL we hand to
/// `SubscriptionService.addSubscription` on tap.
///
/// Endpoint: <https://itunes.apple.com/search?media=podcast&entity=podcast&term=…>
enum ITunesSearchClient {

    /// One row in the search response. Decoded with the JSON keys exactly as
    /// Apple emits them so future fields can be added without a custom
    /// `CodingKeys` mapping.
    struct Result: Decodable, Sendable, Hashable, Identifiable {
        let collectionId: Int
        let collectionName: String
        let artistName: String?
        let feedUrl: String?
        let artworkUrl600: String?
        let artworkUrl100: String?
        let primaryGenreName: String?
        let trackCount: Int?

        var id: Int { collectionId }

        var feedURL: URL? { feedUrl.flatMap { URL(string: $0) } }

        /// Prefer 600px artwork, fall back to the 100px tile.
        var artworkURL: URL? {
            if let s = artworkUrl600, let u = URL(string: s) { return u }
            if let s = artworkUrl100, let u = URL(string: s) { return u }
            return nil
        }
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    /// Searches the iTunes podcast directory. Throws the underlying URLError
    /// or a `DecodingError` so the caller can surface a localized message.
    static func search(_ term: String, limit: Int = 25) async throws -> [Result] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        // Filter out entries with no feed URL — they're nothing we can subscribe to.
        return decoded.results.filter { $0.feedUrl != nil }
    }
}
