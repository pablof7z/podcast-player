import Foundation

// MARK: - Clip

/// A user-authored excerpt of an episode — the foundation of the Snipd-style
/// share flow. Created from the transcript via the long-press composer
/// (UX-03 §6.4 / §6.6) and later rendered as audio + waveform card, video,
/// or deep link by the share-target stack.
///
/// `startMs` / `endMs` are sentence-snapped at composer-commit time so the
/// excerpt always lands on prose boundaries; the optional word-snap mode
/// belongs to v2 of the composer. `transcriptText` is captured *at creation
/// time* so the sharable surface can render even if the underlying transcript
/// is later re-ingested or relocated. `speakerID` is a string (display label
/// or the transcript's `Speaker.id.uuidString`) chosen by the composer when
/// the clip falls inside a single speaker's run; otherwise `nil`.
struct Clip: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let episodeID: UUID
    let subscriptionID: UUID
    /// Sentence-snapped start, milliseconds from the episode origin.
    var startMs: Int
    /// Sentence-snapped end, milliseconds from the episode origin.
    var endMs: Int
    let createdAt: Date
    /// User-editable headline shown above the prose on rendered shares.
    var caption: String?
    /// Speaker handle when the clip falls inside one speaker's run. We store
    /// `Speaker.id.uuidString` (UUIDs are stable within a transcript) so the
    /// share surface can resolve back to the live `Speaker` record.
    var speakerID: String?
    /// The captured prose, frozen at creation time. The transcript is the
    /// source of truth at the moment the user clipped — re-ingesting later
    /// must not silently rewrite a saved excerpt.
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

    /// Wall-clock duration of the clip in seconds.
    var duration: TimeInterval { Double(endMs - startMs) / 1000 }
}
