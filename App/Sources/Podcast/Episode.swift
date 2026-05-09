import Foundation

// TODO: Domain model for a single podcast episode. Will eventually carry
// download state, transcript availability, played/unplayed flags, and a foreign
// key to its `PodcastSubscription`. The spec will pin those fields.

/// A single episode within a `PodcastSubscription`.
struct Episode: Codable, Sendable, Identifiable, Hashable {
    /// Stable local identifier. Distinct from the publisher's `<guid>`.
    var id: UUID
    /// Episode title from the feed.
    var title: String
    /// Publication date from the feed.
    var publishedAt: Date
    /// Direct media URL (MP3 / MP4 / etc.).
    var mediaURL: URL?
    /// Duration in seconds, when known.
    var durationSeconds: TimeInterval?
    /// Show notes / description from the feed (HTML or plain text).
    var summary: String?

    init(
        id: UUID = UUID(),
        title: String,
        publishedAt: Date,
        mediaURL: URL? = nil,
        durationSeconds: TimeInterval? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.publishedAt = publishedAt
        self.mediaURL = mediaURL
        self.durationSeconds = durationSeconds
        self.summary = summary
    }
}
