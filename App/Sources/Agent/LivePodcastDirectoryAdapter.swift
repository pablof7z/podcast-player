import Foundation
import os.log

// MARK: - LivePodcastDirectoryAdapter
//
// Implements `PodcastDirectoryProtocol` using the Apple iTunes Search API
// (https://itunes.apple.com/search). No API key required; results are
// sourced from the Apple Podcasts catalogue.
//
// Endpoint: GET https://itunes.apple.com/search
//   ?term=<query>&media=podcast&entity=<podcast|podcastEpisode>
//   &limit=<n>&country=us&lang=en_us

struct LivePodcastDirectoryAdapter: PodcastDirectoryProtocol {

    private static let logger = Logger.app("PodcastDirectory")
    private static let baseURL = "https://itunes.apple.com/search"

    func searchDirectory(
        query: String,
        type: PodcastDirectorySearchType,
        limit: Int
    ) async throws -> [PodcastDirectoryHit] {
        let entity = type == .podcast ? "podcast" : "podcastEpisode"
        var components = URLComponents(string: Self.baseURL)!
        components.queryItems = [
            URLQueryItem(name: "term",    value: query),
            URLQueryItem(name: "media",   value: "podcast"),
            URLQueryItem(name: "entity",  value: entity),
            URLQueryItem(name: "limit",   value: String(limit)),
            URLQueryItem(name: "country", value: "us"),
            URLQueryItem(name: "lang",    value: "en_us"),
        ]
        guard let url = components.url else {
            throw DirectoryError.badURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DirectoryError.http(http.statusCode)
        }
        return try Self.parse(data: data, type: type)
    }

    // MARK: - Parsing

    private static func parse(data: Data, type: PodcastDirectorySearchType) throws -> [PodcastDirectoryHit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else {
            throw DirectoryError.parseError("Could not parse iTunes Search response")
        }
        return results.compactMap { r in parseHit(r, type: type) }
    }

    private static func parseHit(_ r: [String: Any], type: PodcastDirectorySearchType) -> PodcastDirectoryHit? {
        // Common fields present in both podcast and episode results.
        let podcastTitle = (r["collectionName"] as? String) ?? (r["artistName"] as? String) ?? ""
        guard !podcastTitle.isEmpty else { return nil }
        let author     = r["artistName"] as? String
        let feedURL    = r["feedUrl"] as? String
        let artworkURL = (r["artworkUrl600"] as? String) ?? (r["artworkUrl100"] as? String)
        let collectionID = r["collectionId"] as? Int

        if type == .podcast {
            return PodcastDirectoryHit(
                collectionID: collectionID,
                podcastTitle: podcastTitle,
                author: author,
                feedURL: feedURL,
                artworkURL: artworkURL
            )
        }

        // Episode-specific fields.
        let episodeTitle    = r["trackName"] as? String
        let episodeAudioURL = r["episodeUrl"] as? String
        let episodeGUID     = r["episodeGuid"] as? String
        let episodeDesc     = r["description"] as? String

        let episodePublishedAt: Date? = {
            guard let raw = r["releaseDate"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: raw)
        }()
        let episodeDurationSeconds: Int? = {
            guard let ms = r["trackTimeMillis"] as? Int else { return nil }
            return ms / 1000
        }()

        return PodcastDirectoryHit(
            collectionID: collectionID,
            podcastTitle: podcastTitle,
            author: author,
            feedURL: feedURL,
            artworkURL: artworkURL,
            episodeTitle: episodeTitle,
            episodeAudioURL: episodeAudioURL,
            episodeGUID: episodeGUID,
            episodePublishedAt: episodePublishedAt,
            episodeDurationSeconds: episodeDurationSeconds,
            episodeDescription: episodeDesc
        )
    }
}

// MARK: - LivePodcastSubscribeAdapter

/// Implements `PodcastSubscribeProtocol` using `SubscriptionService`.
final class LivePodcastSubscribeAdapter: PodcastSubscribeProtocol, @unchecked Sendable {

    weak var store: AppStateStore?

    init(store: AppStateStore) {
        self.store = store
    }

    func subscribe(feedURLString: String) async throws -> PodcastSubscribeResult {
        guard let store else {
            throw DirectoryError.unavailable("AppStateStore")
        }
        // Check if already subscribed.
        if let existing = await store.subscription(feedURL: URL(string: feedURLString) ?? URL(fileURLWithPath: "")) {
            let count = await store.episodes(forSubscription: existing.id).count
            return PodcastSubscribeResult(
                podcastID: existing.id.uuidString,
                title: existing.title,
                author: existing.author,
                feedURL: feedURLString,
                episodeCount: count,
                alreadySubscribed: true
            )
        }
        let service = await MainActor.run { SubscriptionService(store: store) }
        let subscription = try await service.addSubscription(feedURLString: feedURLString)
        let count = await store.episodes(forSubscription: subscription.id).count
        return PodcastSubscribeResult(
            podcastID: subscription.id.uuidString,
            title: subscription.title,
            author: subscription.author,
            feedURL: feedURLString,
            episodeCount: count,
            alreadySubscribed: false
        )
    }
}

// MARK: - Error types

enum DirectoryError: LocalizedError {
    case badURL
    case http(Int)
    case parseError(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .badURL:            return "Could not construct directory search URL."
        case .http(let code):   return "iTunes Search API returned HTTP \(code)."
        case .parseError(let m): return "Directory parse error: \(m)"
        case .unavailable(let n): return "\(n) is unavailable."
        }
    }
}
