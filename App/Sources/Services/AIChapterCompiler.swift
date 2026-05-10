import Foundation
import os.log

// MARK: - AIChapterCompiler
//
// Asks the configured LLM (via OpenRouter / Ollama, same provider stack the
// wiki pipeline uses) to synthesise 4–12 chapter boundaries from a ready
// transcript. Persists the result through `AppStateStore.setEpisodeChapters`
// with `Episode.Chapter.isAIGenerated = true` so the player can render an
// "AI" tag.
//
// Design notes
//   • Idempotent — early-returns when the episode already has chapters or
//     transcript isn't `.ready`, so the `TranscriptIngestService` hook can
//     fire-and-forget.
//   • Forces `response_format: json_object` for parse stability — same
//     trick `WikiOpenRouterClient` uses.
//   • Validates monotonic timestamps and clamps to the episode duration
//     before persisting; rejects empty / malformed payloads silently.
//   • Stays read-only against the network — no Scribe / publisher fetches,
//     no chunk re-indexing.

@MainActor
final class AIChapterCompiler {

    // MARK: Singleton

    static let shared = AIChapterCompiler()

    // MARK: Logger

    nonisolated private static let logger = Logger.app("AIChapterCompiler")

    // MARK: Tunables

    /// Cap the transcript bytes we send so the prompt doesn't blow past the
    /// model's context window on long shows. ~28KB is comfortable for any
    /// modern model and still preserves enough structure for chapter inference.
    static let maxTranscriptCharacters: Int = 28_000

    static let minChapters: Int = 4
    static let maxChapters: Int = 12

    /// Cost-ledger feature key. Lives as a literal here (rather than on
    /// `CostFeature`) so this feature stays self-contained — `CostLedger`
    /// accepts arbitrary feature strings and `displayName(for:)` falls back
    /// to the raw key when unrecognised.
    static let costFeatureKey: String = "ai.chapter.compile"

    // MARK: Dedup

    private var inFlight: Set<UUID> = []

    // MARK: API

    /// Compile chapters when (a) the episode has none and (b) the transcript
    /// is `.ready`. No-op otherwise.
    func compileIfNeeded(episodeID: UUID, store: AppStateStore) async {
        guard let episode = store.episode(id: episodeID) else { return }
        if let existing = episode.chapters, !existing.isEmpty { return }
        guard case .ready = episode.transcriptState else { return }
        guard !inFlight.contains(episodeID) else { return }
        inFlight.insert(episodeID)
        defer { inFlight.remove(episodeID) }

        guard let transcript = TranscriptStore.shared.load(episodeID: episodeID) else {
            Self.logger.notice(
                "compileIfNeeded(\(episodeID, privacy: .public)): transcript file missing"
            )
            return
        }
        let modelReference = LLMModelReference(storedID: store.state.settings.wikiModel)
        let apiKey: String
        do {
            guard let resolved = try LLMProviderCredentialResolver.apiKey(for: modelReference.provider),
                  !resolved.isEmpty else {
                Self.logger.info(
                    "compileIfNeeded(\(episodeID, privacy: .public)): no \(modelReference.provider.displayName, privacy: .public) key configured — skipping"
                )
                return
            }
            apiKey = resolved
        } catch {
            Self.logger.error(
                "compileIfNeeded(\(episodeID, privacy: .public)): credential resolve failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        let userPrompt = userPrompt(transcript: transcript, episode: episode)
        let client = WikiOpenRouterClient.live(apiKey: apiKey, model: modelReference.storedID)
        let raw: String
        do {
            raw = try await client.compile(
                systemPrompt: Self.systemPrompt,
                userPrompt: userPrompt,
                feature: Self.costFeatureKey
            )
        } catch {
            Self.logger.error(
                "compileIfNeeded(\(episodeID, privacy: .public)): LLM call failed: \(String(describing: error), privacy: .public)"
            )
            return
        }
        guard let chapters = parseChapters(raw, durationCap: episode.duration) else {
            Self.logger.notice(
                "compileIfNeeded(\(episodeID, privacy: .public)): payload rejected (\(raw.prefix(120), privacy: .public))"
            )
            return
        }
        store.setEpisodeChapters(episodeID, chapters: chapters)
        Self.logger.info(
            "compileIfNeeded(\(episodeID, privacy: .public)): wrote \(chapters.count, privacy: .public) AI chapters"
        )
    }

    // MARK: - Prompting

    private static let systemPrompt: String = """
    You generate clean chapter boundaries for podcast episodes from raw \
    transcripts. Always respond with a single JSON object of the form:
    { "chapters": [ { "start": <seconds>, "title": "<short title>" } ] }
    Rules:
      - Produce between 4 and 12 chapters total.
      - "start" is seconds from the beginning of the episode, integer or float.
      - The first chapter must start at 0.
      - Chapters must be strictly monotonic by "start".
      - Titles are short (max 6 words), descriptive, no quotes, no episode numbers.
      - Skip ad reads — don't create a chapter for them.
      - Prefer topic shifts over speaker changes.
    Respond with ONLY the JSON object. No prose, no markdown fences.
    """

    private func userPrompt(transcript: Transcript, episode: Episode) -> String {
        let lines = transcript.segments.map { seg -> String in
            let ts = Int(seg.start.rounded())
            let cleaned = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "[\(ts)s] \(cleaned)"
        }
        var body = lines.joined(separator: "\n")
        if body.count > Self.maxTranscriptCharacters {
            body = String(body.prefix(Self.maxTranscriptCharacters))
        }
        let durationLine = episode.duration.map { "Episode duration: \(Int($0)) seconds.\n" } ?? ""
        return """
        \(durationLine)Title: \(episode.title)
        Transcript (timestamped):
        \(body)
        """
    }

    // MARK: - Parsing

    /// Decodes `{ "chapters": [...] }`, validates monotonic timestamps, clamps
    /// to `durationCap`, and returns at most `maxChapters` entries. Returns
    /// `nil` if the payload is unusable.
    func parseChapters(_ raw: String, durationCap: TimeInterval?) -> [Episode.Chapter]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        struct Payload: Decodable {
            struct Item: Decodable {
                let start: Double
                let title: String
            }
            let chapters: [Item]
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            return nil
        }
        var prev: Double = -1
        var result: [Episode.Chapter] = []
        for item in payload.chapters {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let cap = durationCap ?? Double.greatestFiniteMagnitude
            let clamped = max(0, min(item.start, cap))
            // Strict monotonic: each timestamp must be > previous.
            guard clamped > prev else { continue }
            prev = clamped
            result.append(Episode.Chapter(
                startTime: clamped,
                title: title,
                isAIGenerated: true
            ))
            if result.count >= Self.maxChapters { break }
        }
        guard result.count >= Self.minChapters else { return nil }
        // First chapter pinned to 0 — overrides minor LLM drift.
        if result.first!.startTime > 0 {
            var first = result[0]
            first.startTime = 0
            result[0] = first
        }
        return result
    }
}
