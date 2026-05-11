import Foundation

/// A single podcast feed the user follows.
///
/// Field shape comes from `docs/spec/briefs/ux-02-library.md` plus
/// `docs/spec/baseline-podcast-features.md` §2 (subscription & feed).
/// Designed to migrate to a SwiftData `@Model` later (see
/// `docs/spec/research/template-architecture-and-extension-plan.md` §6); fields
/// are flat value types, no reference cycles.
///
/// HTTP cache headers (`etag`, `lastModified`) live on the subscription so a
/// conditional GET can short-circuit polling — see `FeedClient`.
struct PodcastSubscription: Codable, Sendable, Identifiable, Hashable {
    /// Stable local identifier. Generated locally on import; not the
    /// publisher's GUID. Used by `Episode.subscriptionID` and by every UI
    /// surface that needs to reference a show.
    var id: UUID
    /// Original RSS / Atom feed URL.
    var feedURL: URL
    /// Podcast title from the feed (`<channel><title>`).
    var title: String
    /// Author / publisher display string (`<itunes:author>` ?? `<channel><author>`).
    var author: String
    /// Cover-art URL (largest available variant: `<itunes:image>` then `<image><url>`).
    var imageURL: URL?
    /// Free-form description from the feed (`<description>` / `<itunes:summary>`).
    var description: String
    /// BCP-47 language tag from `<language>` when present.
    var language: String?
    /// `<itunes:category>` text values, deduped, ordered as encountered.
    var categories: [String]
    /// When the user added this subscription.
    var subscribedAt: Date
    /// Wall-clock of the last successful (200/304) feed fetch.
    var lastRefreshedAt: Date?

    // MARK: - HTTP cache

    /// `ETag` from the most recent feed response. Sent back as `If-None-Match`.
    var etag: String?
    /// `Last-Modified` from the most recent feed response. Sent back as
    /// `If-Modified-Since`. Stored as the raw HTTP date string to avoid
    /// timezone re-parsing churn.
    var lastModified: String?

    // MARK: - User preferences

    /// Per-show download policy (off / latest-N / all-new + Wi-Fi guard).
    var autoDownload: AutoDownloadPolicy
    /// Per-show notification toggle. Library brief §2.2 / baseline §6.
    var notificationsEnabled: Bool
    /// Optional per-show playback rate override; falls back to
    /// `Settings.defaultPlaybackRate` when `nil`.
    var defaultPlaybackRate: Double?
    /// `true` for the synthetic "Agent Generated" show that the AI agent uses
    /// to publish locally-synthesised episodes. These entries are excluded from
    /// OPML export, feed refresh, and download heuristics.
    var isAgentGenerated: Bool

    init(
        id: UUID = UUID(),
        feedURL: URL,
        title: String,
        author: String = "",
        imageURL: URL? = nil,
        description: String = "",
        language: String? = nil,
        categories: [String] = [],
        subscribedAt: Date = Date(),
        lastRefreshedAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        autoDownload: AutoDownloadPolicy = .default,
        notificationsEnabled: Bool = true,
        defaultPlaybackRate: Double? = nil,
        isAgentGenerated: Bool = false
    ) {
        self.id = id
        self.feedURL = feedURL
        self.title = title
        self.author = author
        self.imageURL = imageURL
        self.description = description
        self.language = language
        self.categories = categories
        self.subscribedAt = subscribedAt
        self.lastRefreshedAt = lastRefreshedAt
        self.etag = etag
        self.lastModified = lastModified
        self.autoDownload = autoDownload
        self.notificationsEnabled = notificationsEnabled
        self.defaultPlaybackRate = defaultPlaybackRate
        self.isAgentGenerated = isAgentGenerated
    }

    // MARK: - Codable (forward-compat decoding)

    private enum CodingKeys: String, CodingKey {
        case id, feedURL, title, author, imageURL, description
        case language, categories, subscribedAt, lastRefreshedAt
        case etag, lastModified
        case autoDownload, notificationsEnabled, defaultPlaybackRate
        case isAgentGenerated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        feedURL = try c.decode(URL.self, forKey: .feedURL)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        subscribedAt = try c.decodeIfPresent(Date.self, forKey: .subscribedAt) ?? Date()
        lastRefreshedAt = try c.decodeIfPresent(Date.self, forKey: .lastRefreshedAt)
        etag = try c.decodeIfPresent(String.self, forKey: .etag)
        lastModified = try c.decodeIfPresent(String.self, forKey: .lastModified)
        autoDownload = try c.decodeIfPresent(AutoDownloadPolicy.self, forKey: .autoDownload) ?? .default
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        defaultPlaybackRate = try c.decodeIfPresent(Double.self, forKey: .defaultPlaybackRate)
        isAgentGenerated = try c.decodeIfPresent(Bool.self, forKey: .isAgentGenerated) ?? false
    }
}
