import Foundation

// TODO: Timestamped transcript model with optional speaker diarization.
// Will be sourced from the publisher when available, otherwise transcribed via
// ElevenLabs Scribe (or equivalent). Chunks feed the embeddings/RAG pipeline.

/// A timestamped transcript for a single `Episode`.
struct Transcript: Codable, Sendable, Identifiable, Hashable {
    /// Stable identifier; one transcript per episode.
    var id: UUID
    /// Title for human display (typically the episode title).
    var title: String
    /// When this transcript was generated or last updated.
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.generatedAt = generatedAt
    }
}
