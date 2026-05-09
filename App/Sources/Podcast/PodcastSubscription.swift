import Foundation

// TODO: Domain model for a podcast a user has subscribed to (RSS / OPML import,
// artwork, refresh cadence, notification preferences). Spec will define the
// canonical field set; for now this is a minimal `Identifiable` skeleton.

/// A single podcast feed the user follows.
struct PodcastSubscription: Codable, Sendable, Identifiable, Hashable {
    /// Stable identifier. Generated locally on import; not the publisher's GUID.
    var id: UUID
    /// Podcast title from the RSS feed.
    var title: String
    /// Original RSS / Atom feed URL.
    var feedURL: URL
    /// Cover-art URL (largest available variant).
    var artworkURL: URL?
    /// Author / publisher display string.
    var author: String?
    /// Free-form description from the feed.
    var summary: String?
    /// When the user added this subscription.
    var subscribedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        feedURL: URL,
        artworkURL: URL? = nil,
        author: String? = nil,
        summary: String? = nil,
        subscribedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.author = author
        self.summary = summary
        self.subscribedAt = subscribedAt
    }
}
