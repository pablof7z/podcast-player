import Foundation

/// A captured snippet of an episode — span-grounded, optionally transcript-anchored.
///
/// Stub introduced by the auto-snip / AI-chapters agent. The sister "clips"
/// agent owns the canonical model and persistence; this file exists only so
/// dependent call sites compile when the sister agent's branch hasn't landed
/// yet. Field shape matches the brief in `docs/spec/research/snipd-feature-model.md`
/// §"Snip Artifact Shape" — kept minimal and forward-compatible (every optional
/// decoded with `decodeIfPresent`).
struct Clip: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var episodeID: UUID
    var subscriptionID: UUID
    /// Inclusive start in milliseconds from the episode origin.
    var startMs: Int
    /// Exclusive end in milliseconds from the episode origin.
    var endMs: Int
    var createdAt: Date
    /// Optional human-friendly title — populated by the user or by an LLM
    /// summarisation pass after capture.
    var caption: String?
    /// Plain-text transcript window, when the episode has a ready transcript.
    var transcriptText: String?
    /// Diarized speaker (if known) at the moment of capture.
    var speakerID: UUID?
    /// How the clip was triggered. `auto` is the headphone / lock-screen path;
    /// `touch` is the in-app button. Sister agent may extend this enum.
    var source: Source

    enum Source: String, Codable, Sendable, Hashable {
        case auto
        case touch
        case headphone
        case carplay
        case watch
        case siri
        case agent
    }

    init(
        id: UUID = UUID(),
        episodeID: UUID,
        subscriptionID: UUID,
        startMs: Int,
        endMs: Int,
        createdAt: Date = Date(),
        caption: String? = nil,
        transcriptText: String? = nil,
        speakerID: UUID? = nil,
        source: Source = .touch
    ) {
        self.id = id
        self.episodeID = episodeID
        self.subscriptionID = subscriptionID
        self.startMs = startMs
        self.endMs = endMs
        self.createdAt = createdAt
        self.caption = caption
        self.transcriptText = transcriptText
        self.speakerID = speakerID
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id, episodeID, subscriptionID, startMs, endMs, createdAt
        case caption, transcriptText, speakerID, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        episodeID = try c.decode(UUID.self, forKey: .episodeID)
        subscriptionID = try c.decode(UUID.self, forKey: .subscriptionID)
        startMs = try c.decode(Int.self, forKey: .startMs)
        endMs = try c.decode(Int.self, forKey: .endMs)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        transcriptText = try c.decodeIfPresent(String.self, forKey: .transcriptText)
        speakerID = try c.decodeIfPresent(UUID.self, forKey: .speakerID)
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .touch
    }
}
