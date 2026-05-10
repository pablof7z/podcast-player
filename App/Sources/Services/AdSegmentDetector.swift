import Foundation
import os.log

// MARK: - AdSegmentDetector
//
// Asks the configured LLM (via OpenRouter / Ollama, same provider stack the
// wiki + AI chapter pipelines use) to find ad-read spans inside a ready
// transcript. Persists the result onto `Episode.adSegments`.
//
// Design notes (parallels `AIChapterCompiler`)
//   • Idempotent — early-returns when the episode already has cached ad
//     segments OR the transcript isn't `.ready`. Empty array counts as
//     cached: "detection ran, found no ads".
//   • Forces `response_format: json_object` for parse stability.
//   • Validates monotonic + non-overlapping ranges and clamps to the
//     episode duration before persisting.
//   • Stays read-only against the network — no Scribe / publisher fetches
//     and no chunk re-indexing.

@MainActor
final class AdSegmentDetector {

    // MARK: Singleton

    static let shared = AdSegmentDetector()

    // MARK: Logger

    nonisolated private static let logger = Logger.app("AdSegmentDetector")

    // MARK: Tunables

    /// Cap the transcript bytes we send so the prompt doesn't blow past the
    /// model's context window. Matches `AIChapterCompiler.maxTranscriptCharacters`
    /// — ~28 KB is comfortable for any modern model and still preserves
    /// enough structure to spot ad reads.
    static let maxTranscriptCharacters: Int = 28_000

    /// Cost-ledger feature key. Free-form string — see
    /// `AIChapterCompiler.costFeatureKey` rationale.
    static let costFeatureKey: String = "ad.segment.detect"

    // MARK: Dedup

    private var inFlight: Set<UUID> = []

    // MARK: API

    /// Detect ad segments when (a) the transcript is `.ready` and (b) the
    /// episode doesn't already have cached `adSegments`. No-op otherwise.
    func detectIfNeeded(episodeID: UUID, store: AppStateStore) async {
        guard let episode = store.episode(id: episodeID) else { return }
        guard episode.adSegments == nil else { return }
        guard case .ready = episode.transcriptState else { return }
        guard !inFlight.contains(episodeID) else { return }
        inFlight.insert(episodeID)
        defer { inFlight.remove(episodeID) }

        guard let transcript = TranscriptStore.shared.load(episodeID: episodeID) else {
            Self.logger.notice(
                "detectIfNeeded(\(episodeID, privacy: .public)): transcript file missing"
            )
            return
        }
        let modelReference = LLMModelReference(storedID: store.state.settings.wikiModel)
        let apiKey: String
        do {
            guard let resolved = try LLMProviderCredentialResolver.apiKey(for: modelReference.provider),
                  !resolved.isEmpty else {
                Self.logger.info(
                    "detectIfNeeded(\(episodeID, privacy: .public)): no \(modelReference.provider.displayName, privacy: .public) key configured — skipping"
                )
                return
            }
            apiKey = resolved
        } catch {
            Self.logger.error(
                "detectIfNeeded(\(episodeID, privacy: .public)): credential resolve failed: \(String(describing: error), privacy: .public)"
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
                "detectIfNeeded(\(episodeID, privacy: .public)): LLM call failed: \(String(describing: error), privacy: .public)"
            )
            return
        }
        let segments = parseAdSegments(raw, durationCap: episode.duration) ?? []
        // Persist either the detected list or an explicit empty marker so we
        // don't keep re-running detection on every episode open.
        store.setEpisodeAdSegments(episodeID, segments: segments)
        Self.logger.info(
            "detectIfNeeded(\(episodeID, privacy: .public)): wrote \(segments.count, privacy: .public) ad segments"
        )
    }

    // MARK: - Prompting

    private static let systemPrompt: String = """
    You identify advertisement reads inside podcast episode transcripts. \
    Always respond with a single JSON object of the form:
    { "ads": [ { "start_seconds": <number>, "end_seconds": <number>, "kind": "preroll"|"midroll"|"postroll" } ] }
    Rules:
      - Only mark spans that are clearly advertisements (host-read or pre-recorded sponsor copy).
      - Do NOT mark guest plugs, book recommendations, or off-topic asides.
      - "start_seconds" / "end_seconds" are seconds from the start of the episode; end must be greater than start.
      - Ranges must be non-overlapping and strictly increasing by "start_seconds".
      - "kind": "preroll" if before any topical content; "postroll" if after; otherwise "midroll".
      - Return an empty array if the episode has no ads.
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

    /// Decodes `{ "ads": [...] }`, validates strictly increasing,
    /// non-overlapping ranges, clamps to `durationCap`, and returns the list.
    /// Returns `nil` if the payload itself is unparseable; an empty list is a
    /// valid "no ads found" signal.
    func parseAdSegments(
        _ raw: String,
        durationCap: TimeInterval?
    ) -> [Episode.AdSegment]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        struct Payload: Decodable {
            struct Item: Decodable {
                let start_seconds: Double
                let end_seconds: Double
                let kind: String?
            }
            let ads: [Item]
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            return nil
        }
        let cap = durationCap ?? Double.greatestFiniteMagnitude
        var prevEnd: Double = -1
        var result: [Episode.AdSegment] = []
        for item in payload.ads {
            let start = max(0, min(item.start_seconds, cap))
            let end = max(0, min(item.end_seconds, cap))
            // Reject non-positive ranges and ranges that would overlap (or
            // touch) the previous span — the auto-skip loop relies on
            // strictly disjoint intervals to throttle one skip per segment.
            guard end > start else { continue }
            guard start >= prevEnd else { continue }
            let kind = Episode.AdKind(rawValue: item.kind ?? "midroll") ?? .midroll
            result.append(Episode.AdSegment(start: start, end: end, kind: kind))
            prevEnd = end
        }
        return result
    }
}

// MARK: - Chapter overlap helper

extension Episode.Chapter {
    /// `true` when this chapter's `[startTime, effectiveEnd)` window
    /// overlaps any of `adSegments`. Used by `PlayerChaptersScrollView` to
    /// flag rows with the amber stripe + `speaker.slash` glyph.
    ///
    /// `chapters` is the full list so the helper can resolve an implicit
    /// `endTime` from the next chapter's `startTime` when this chapter has
    /// no explicit `endTime`. For the last chapter we treat the end as
    /// `+∞` — any ad after `startTime` overlaps.
    func overlapsAd(
        in chapters: [Episode.Chapter],
        adSegments: [Episode.AdSegment]
    ) -> Bool {
        guard !adSegments.isEmpty else { return false }
        let effectiveEnd: TimeInterval
        if let end = endTime {
            effectiveEnd = end
        } else if let idx = chapters.firstIndex(where: { $0.id == id }),
                  chapters.index(after: idx) < chapters.endIndex {
            effectiveEnd = chapters[chapters.index(after: idx)].startTime
        } else {
            effectiveEnd = .greatestFiniteMagnitude
        }
        return adSegments.contains { ad in
            ad.start < effectiveEnd && ad.end > startTime
        }
    }
}
