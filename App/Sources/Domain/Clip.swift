import Foundation

// MARK: - Clip
//
// Stub matching the spec handed down by the EpisodeDetail/Clip composer
// branch. The sister agent owns the canonical model; this file exists so the
// share-target work can compile and link against the same shape. When their
// branch lands, this file will either be replaced or merged — keep the
// shape verbatim. See the share-targets commit message for context.
struct Clip: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var episodeID: UUID
    var subscriptionID: UUID
    /// Inclusive start of the audio span, in milliseconds from episode origin.
    var startMs: Int
    /// Exclusive end of the audio span, in milliseconds from episode origin.
    var endMs: Int
    var createdAt: Date
    /// Optional user-authored caption surfaced in the share card / video.
    var caption: String?
    /// Loose reference to the speaker that owns the dominant voice in the
    /// span. Stored as a string per the composer's contract — may be a
    /// `Speaker.id.uuidString`, a raw label, or nil when unknown.
    var speakerID: String?
    /// Verbatim transcript text covering the span. Pre-trimmed by the
    /// composer (no leading/trailing whitespace, no surrounding quotes).
    var transcriptText: String

    init(
        id: UUID = UUID(),
        episodeID: UUID,
        subscriptionID: UUID,
        startMs: Int,
        endMs: Int,
        createdAt: Date = Date(),
        caption: String? = nil,
        speakerID: String? = nil,
        transcriptText: String
    ) {
        self.id = id
        self.episodeID = episodeID
        self.subscriptionID = subscriptionID
        self.startMs = startMs
        self.endMs = endMs
        self.createdAt = createdAt
        self.caption = caption
        self.speakerID = speakerID
        self.transcriptText = transcriptText
    }
}

extension Clip {
    /// Start time as seconds, convenient for `AVAsset` / `CMTime` math.
    var startSeconds: TimeInterval { TimeInterval(startMs) / 1000.0 }
    /// End time as seconds.
    var endSeconds: TimeInterval { TimeInterval(endMs) / 1000.0 }
    /// Span duration in seconds. Always non-negative.
    var durationSeconds: TimeInterval { max(0, endSeconds - startSeconds) }
}
