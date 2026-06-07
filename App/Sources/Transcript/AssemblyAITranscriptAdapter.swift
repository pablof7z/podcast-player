import Foundation

extension Transcript {
    /// Converts an AssemblyAI completed payload into our internal `Transcript`.
    ///
    /// Segment-building strategy:
    /// - If `utterances` is populated, use one `Segment` per utterance.
    /// - Otherwise, group raw `words` into approximate sentence segments using
    ///   a 1.5 s pause boundary heuristic.
    static func fromAssemblyAI(
        _ payload: AssemblyAITranscriptPayload,
        episodeID: UUID,
        languageHint: String?
    ) -> Transcript {
        let language = payload.language_code ?? languageHint ?? "en-US"
        var speakers: [String: Speaker] = [:]
        if let utterances = payload.utterances {
            for utterance in utterances {
                guard let label = utterance.speaker,
                      !label.isEmpty,
                      speakers[label] == nil else { continue }
                speakers[label] = Speaker(label: label, displayName: "Speaker \(label)")
            }
        }

        let segments: [Segment]
        if let utterances = payload.utterances, !utterances.isEmpty {
            segments = utterances.map { utterance in
                let words = (utterance.words ?? []).map { word in
                    Word(
                        start: Double(word.start) / 1000.0,
                        end: Double(word.end) / 1000.0,
                        text: word.text
                    )
                }
                return Segment(
                    start: Double(utterance.start) / 1000.0,
                    end: Double(utterance.end) / 1000.0,
                    speakerID: utterance.speaker.flatMap { speakers[$0]?.id },
                    text: utterance.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    words: words.isEmpty ? nil : words
                )
            }
        } else {
            segments = groupAssemblyAIWordsIntoSegments(payload.words ?? [])
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

    private static func groupAssemblyAIWordsIntoSegments(_ words: [AssemblyAIWord]) -> [Segment] {
        guard !words.isEmpty else { return [] }
        let pauseBoundary = 1.5
        var segments: [Segment] = []
        var bufferStart = Double(words[0].start) / 1000.0
        var bufferEnd = Double(words[0].end) / 1000.0
        var bufferText = words[0].text
        var bufferWords: [Word] = [
            Word(
                start: Double(words[0].start) / 1000.0,
                end: Double(words[0].end) / 1000.0,
                text: words[0].text
            )
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
