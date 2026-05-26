import Foundation

// MARK: - DTOs

struct AssemblyAIJob: Sendable, Hashable {
    let transcriptID: String
    let episodeID: UUID
    let createdAt: Date
    let languageHint: String?
    /// Verbatim `speech_models` list submitted. Surfaced on the cost-ledger
    /// record so the Usage view shows which model the user picked even though
    /// AssemblyAI's response doesn't echo it.
    let speechModels: [String]
}

/// Single response shape that covers both the submit reply and the poll reply
/// - they're the same envelope, differing only in which fields are populated.
struct AssemblyAITranscriptPayload: Codable, Sendable, Hashable {
    let id: String?
    let status: String?
    let audio_url: String?
    let audio_duration: Double?     // seconds (the one exception to ms timestamps)
    let language_code: String?
    let text: String?
    let error: String?
    let words: [AssemblyAIWord]?
    let utterances: [AssemblyAIUtterance]?
    /// Billing / usage telemetry populated on the completed poll. Per
    /// AssemblyAI's OpenAPI: `cost` is USD, `seconds` is the audio duration
    /// processed, `input_tokens` / `output_tokens` are model-side counts.
    let usage: AssemblyAIUsage?
}

struct AssemblyAIUsage: Codable, Sendable, Hashable {
    let cost: Double?
    let seconds: Double?
    let input_tokens: Int?
    let output_tokens: Int?
    let total_tokens: Int?
}

/// Utterance = diarized turn. Mapped 1:1 onto our `Transcript.Segment` when
/// `speaker_labels=true`. Timestamps are MILLISECONDS - convert to seconds at
/// the adapter boundary.
struct AssemblyAIUtterance: Codable, Sendable, Hashable {
    let start: Int
    let end: Int
    let text: String
    let confidence: Double?
    let speaker: String?
    let words: [AssemblyAIWord]?
}

/// Word with character-level timestamps. AssemblyAI always returns these on
/// pre-recorded transcripts. Timestamps in MILLISECONDS.
struct AssemblyAIWord: Codable, Sendable, Hashable {
    let start: Int
    let end: Int
    let text: String
    let confidence: Double?
    let speaker: String?
}

// MARK: - Transcript adapter

extension Transcript {
    /// Converts an AssemblyAI completed payload into our internal `Transcript`.
    ///
    /// Segment-building strategy:
    ///   - If `utterances` is populated (speaker_labels was on) -> use one
    ///     `Segment` per utterance. Speaker IDs from "A", "B"... map onto our
    ///     `Speaker` records.
    ///   - Otherwise -> group raw `words` into approximate sentence segments
    ///     using a 1.5 s pause boundary heuristic. Mirrors the Scribe adapter's
    ///     behaviour when diarization is off.
    ///
    /// Timestamps in milliseconds are converted to seconds at this boundary so
    /// the rest of the app keeps its `TimeInterval`-in-seconds invariant.
    static func fromAssemblyAI(
        _ payload: AssemblyAITranscriptPayload,
        episodeID: UUID,
        languageHint: String?
    ) -> Transcript {
        let language = payload.language_code ?? languageHint ?? "en-US"

        // Build the speakers map first so segment construction can reference it.
        var speakers: [String: Speaker] = [:]
        if let utterances = payload.utterances {
            for u in utterances {
                guard let label = u.speaker, !label.isEmpty, speakers[label] == nil else { continue }
                speakers[label] = Speaker(label: label, displayName: "Speaker \(label)")
            }
        }

        let segments: [Segment]
        if let utterances = payload.utterances, !utterances.isEmpty {
            segments = utterances.map { u in
                let words = (u.words ?? []).map { w in
                    Word(
                        start: Double(w.start) / 1000.0,
                        end: Double(w.end) / 1000.0,
                        text: w.text
                    )
                }
                return Segment(
                    start: Double(u.start) / 1000.0,
                    end: Double(u.end) / 1000.0,
                    speakerID: u.speaker.flatMap { speakers[$0]?.id },
                    text: u.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    words: words.isEmpty ? nil : words
                )
            }
        } else {
            // No diarization - group words into pseudo-segments at pause boundaries.
            segments = groupWordsIntoSegments(payload.words ?? [])
        }

        return Transcript(
            episodeID: episodeID,
            language: language,
            source: .assemblyAI,
            segments: segments,
            speakers: Array(speakers.values),
            generatedAt: Date()
        )
    }

    /// Falls-back segment construction when `utterances` is absent. 1.5 s pause
    /// boundary keeps segments human-sized for the player's transcript view
    /// without losing AIChapterCompiler's anchoring (it only needs timestamped
    /// lines, not perfect sentence breaks).
    private static func groupWordsIntoSegments(_ words: [AssemblyAIWord]) -> [Segment] {
        guard !words.isEmpty else { return [] }
        let pauseBoundary = 1.5
        var segments: [Segment] = []
        var bufferStart = Double(words[0].start) / 1000.0
        var bufferEnd = Double(words[0].end) / 1000.0
        var bufferText = words[0].text
        var bufferWords: [Word] = [
            Word(start: Double(words[0].start) / 1000.0,
                 end: Double(words[0].end) / 1000.0,
                 text: words[0].text)
        ]

        func flush() {
            let trimmed = bufferText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            segments.append(Segment(
                start: bufferStart,
                end: bufferEnd,
                speakerID: nil,
                text: trimmed,
                words: bufferWords.isEmpty ? nil : bufferWords
            ))
        }

        for word in words.dropFirst() {
            let start = Double(word.start) / 1000.0
            let end = Double(word.end) / 1000.0
            if start - bufferEnd >= pauseBoundary {
                flush()
                bufferStart = start
                bufferEnd = end
                bufferText = word.text
                bufferWords = [Word(start: start, end: end, text: word.text)]
            } else {
                bufferText += " " + word.text
                bufferEnd = end
                bufferWords.append(Word(start: start, end: end, text: word.text))
            }
        }
        flush()
        return segments
    }
}
