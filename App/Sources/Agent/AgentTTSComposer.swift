import AVFoundation
import Foundation
import os.log

// MARK: - AgentTTSComposer
//
// Synthesises a sequence of `TTSTurn` values into a single stitched m4a and
// publishes the result as a new episode on the agent-generated virtual podcast.
//
// Turn types:
//   .speech   — text → ElevenLabs TTS → temp mp3 → stitched in
//   .snippet  — existing episode clip → time-trimmed via BriefingAudioStitcher
//
// After stitching, a `Transcript` is built from the turn text and saved to
// `TranscriptStore`. Chapters are synthesised directly from the turn structure
// (consecutive speech turns collapse into a single chapter; each snippet turn
// gets its own chapter with the source episode's artwork and `sourceEpisodeID`).
// `adSegments` is set to `[]` so `AIChapterCompiler` skips re-processing.

final class AgentTTSComposer: TTSPublisherProtocol, @unchecked Sendable {

    // MARK: - Dependencies

    private let ttsClient: ElevenLabsTTSClient
    weak var store: AppStateStore?
    weak var playback: PlaybackState?

    private static let logger = Logger.app("AgentTTSComposer")

    // MARK: - Voice configuration

    private static let defaultVoiceIDKey = "io.f7z.podcast.agent.defaultVoiceID"

    init(store: AppStateStore, playback: PlaybackState) {
        self.store = store
        self.playback = playback
        self.ttsClient = ElevenLabsTTSClient()
    }

    func defaultVoiceID() -> String {
        UserDefaults.standard.string(forKey: Self.defaultVoiceIDKey)
            ?? ElevenLabsTTSClient.defaultVoiceID
    }

    func setDefaultVoiceID(_ voiceID: String) {
        UserDefaults.standard.set(voiceID, forKey: Self.defaultVoiceIDKey)
    }

    // MARK: - TTSPublisherProtocol

    func generateAndPublish(
        title: String,
        description: String?,
        turns: [TTSTurn],
        playNow: Bool
    ) async throws -> TTSEpisodeResult {
        guard !turns.isEmpty else {
            throw AgentTTSError.emptyTurns
        }
        guard ttsClient.isConfigured else {
            throw AgentTTSError.notConfigured
        }

        // 1. Build BriefingTrack list (one per turn).
        let (tracks, trackDurations) = try await buildTracks(for: turns)

        // 2. Stitch tracks into a single m4a.
        let episodeID = UUID()
        let outputURL = try AgentGeneratedPodcastService.audioFileURL(episodeID: episodeID)
        let durationSeconds = try await BriefingAudioStitcher.stitch(tracks: tracks, outputURL: outputURL)

        // 3. Build chapters and transcript from turns + resolved durations.
        let (chapters, transcript) = await buildChaptersAndTranscript(
            turns: turns,
            trackDurations: trackDurations,
            episodeID: episodeID
        )

        // 4. Register the episode and optionally start playback.
        let episode = await MainActor.run {
            guard let store else { return Optional<Episode>.none }
            return AgentGeneratedPodcastService.publishEpisode(
                title: title,
                description: description ?? "",
                audioURL: outputURL,
                durationSeconds: durationSeconds,
                in: store
            )
        }

        guard let episode else {
            throw AgentTTSError.storeUnavailable
        }

        // 5. Persist transcript, chapters, and set adSegments = [] so
        //    AIChapterCompiler skips this already-structured episode.
        await MainActor.run {
            guard let store else { return }
            try? TranscriptStore.shared.save(transcript)
            store.setEpisodeTranscriptState(episode.id, state: .ready(source: .other))
            store.setEpisodeChapters(episode.id, chapters: chapters)
            store.setEpisodeAdSegments(episode.id, segments: [])
        }

        // 6. Optionally start playback.
        if playNow {
            await MainActor.run {
                guard let playback else { return }
                playback.setEpisode(episode)
                playback.seek(to: 0)
                playback.play()
            }
        }

        let subscriptionID = await MainActor.run {
            store?.subscription(feedURL: AgentGeneratedPodcastService.sentinelFeedURL)?.id.uuidString ?? ""
        }

        return TTSEpisodeResult(
            episodeID: episode.id.uuidString,
            podcastID: subscriptionID,
            title: title,
            durationSeconds: durationSeconds,
            publishedToLibrary: true
        )
    }

    // MARK: - Track building

    /// Builds `BriefingTrack` values and returns the per-turn audio duration
    /// so the chapter builder can compute cumulative start times.
    private func buildTracks(for turns: [TTSTurn]) async throws -> ([BriefingTrack], [Double]) {
        var tracks: [BriefingTrack] = []
        var durations: [Double] = []
        let dummySegmentID = UUID()

        for (index, turn) in turns.enumerated() {
            switch turn.kind {
            case .speech(let text, let voiceIDOverride):
                let voice = voiceIDOverride ?? defaultVoiceID()
                let audioURL = try await synthesizeSpeech(text: text, voiceID: voice, index: index)
                let duration = try await audioDuration(of: audioURL)
                tracks.append(BriefingTrack(
                    segmentID: dummySegmentID,
                    indexInSegment: index,
                    kind: .tts,
                    audioURL: audioURL,
                    startInTrackSeconds: 0,
                    endInTrackSeconds: duration,
                    transcriptText: text
                ))
                durations.append(duration)

            case .snippet(let episodeID, let start, let end, let label):
                guard let enclosureURL = await resolveEpisodeAudio(episodeID: episodeID) else {
                    throw AgentTTSError.snippetNotDownloaded(episodeID: episodeID)
                }
                let duration = end - start
                tracks.append(BriefingTrack(
                    segmentID: dummySegmentID,
                    indexInSegment: index,
                    kind: .quote,
                    audioURL: enclosureURL,
                    startInTrackSeconds: start,
                    endInTrackSeconds: end,
                    transcriptText: label ?? ""
                ))
                durations.append(duration)
            }
        }

        return (tracks, durations)
    }

    // MARK: - Chapter + transcript building

    /// Converts the turn sequence into `Episode.Chapter` values and a
    /// `Transcript`. Consecutive speech turns collapse into a single chapter;
    /// each snippet turn gets its own chapter with the source episode's
    /// artwork URL and `sourceEpisodeID` set for the player chip.
    private func buildChaptersAndTranscript(
        turns: [TTSTurn],
        trackDurations: [Double],
        episodeID: UUID
    ) async -> ([Episode.Chapter], Transcript) {
        var chapters: [Episode.Chapter] = []
        var transcriptSegments: [Segment] = []
        var cursor: TimeInterval = 0

        // Accumulator for consecutive speech turns.
        var speechStart: TimeInterval?
        var speechTexts: [String] = []

        func flushSpeechChapter() {
            guard !speechTexts.isEmpty, let start = speechStart else { return }
            let combinedText = speechTexts.joined(separator: " ")
            let preview = String(combinedText.prefix(60))
            let chapterTitle = combinedText.count <= 60 ? combinedText : preview + "…"
            chapters.append(Episode.Chapter(
                startTime: start,
                title: chapterTitle,
                isAIGenerated: true
            ))
            speechStart = nil
            speechTexts = []
        }

        for (index, turn) in turns.enumerated() {
            let duration = index < trackDurations.count ? trackDurations[index] : 0
            guard duration > 0 else {
                cursor += duration
                continue
            }

            switch turn.kind {
            case .speech(let text, _):
                if speechStart == nil { speechStart = cursor }
                speechTexts.append(text)

                // Each speech turn is a transcript segment.
                transcriptSegments.append(Segment(
                    start: cursor,
                    end: cursor + duration,
                    text: text
                ))

            case .snippet(let sourceID, _, _, let label):
                // Close any open speech chapter first.
                flushSpeechChapter()

                // Resolve the source episode's artwork for the mid-play swap.
                let artworkURL = await MainActor.run { [weak self] () -> URL? in
                    guard let self, let store = self.store else { return nil }
                    guard let uuid = UUID(uuidString: sourceID),
                          let ep = store.episode(id: uuid) else { return nil }
                    return ep.imageURL ?? store.subscription(id: ep.subscriptionID)?.imageURL
                }

                let chapterTitle = label?.isEmpty == false
                    ? label!
                    : await resolveEpisodeTitle(episodeID: sourceID)

                chapters.append(Episode.Chapter(
                    startTime: cursor,
                    title: chapterTitle,
                    imageURL: artworkURL,
                    isAIGenerated: true,
                    sourceEpisodeID: sourceID
                ))

                // Snippet text becomes a transcript segment too.
                if let labelText = label, !labelText.isEmpty {
                    transcriptSegments.append(Segment(
                        start: cursor,
                        end: cursor + duration,
                        text: labelText
                    ))
                }
            }

            cursor += duration
        }

        // Flush any trailing speech turns.
        flushSpeechChapter()

        let transcript = Transcript(
            episodeID: episodeID,
            language: "en",
            source: .onDevice,
            segments: transcriptSegments
        )

        return (chapters, transcript)
    }

    // MARK: - Speech synthesis → temp file

    private func synthesizeSpeech(text: String, voiceID: String, index: Int) async throws -> URL {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-tts-\(index)-\(UUID().uuidString).mp3")

        var collectedData = Data()
        let stream = ttsClient.synthesizeStream(text: text, voiceID: voiceID)
        for try await chunk in stream {
            collectedData.append(chunk)
        }

        guard !collectedData.isEmpty else {
            throw AgentTTSError.emptyAudioData(index: index)
        }

        try collectedData.write(to: tmpURL, options: .atomic)
        Self.logger.debug("AgentTTSComposer: synthesised turn \(index, privacy: .public) → \(tmpURL.lastPathComponent, privacy: .public)")
        return tmpURL
    }

    // MARK: - Episode audio resolution

    private func resolveEpisodeAudio(episodeID: EpisodeID) async -> URL? {
        guard let uuid = UUID(uuidString: episodeID) else { return nil }
        return await MainActor.run {
            guard let episode = store?.episode(id: uuid) else { return nil }
            guard case .downloaded = episode.downloadState else { return nil }
            let localURL = EpisodeDownloadStore.shared.localFileURL(for: episode)
            return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
        }
    }

    private func resolveEpisodeTitle(episodeID: String) async -> String {
        await MainActor.run {
            guard let uuid = UUID(uuidString: episodeID),
                  let episode = store?.episode(id: uuid) else {
                return "Clip"
            }
            return episode.title
        }
    }

    // MARK: - Audio duration helper

    private func audioDuration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds > 0 ? seconds : 1.0
        } catch {
            Self.logger.warning("AgentTTSComposer: could not load duration for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return 60.0
        }
    }
}

// MARK: - Errors

enum AgentTTSError: LocalizedError {
    case emptyTurns
    case notConfigured
    case emptyAudioData(index: Int)
    case storeUnavailable
    case snippetNotDownloaded(episodeID: String)

    var errorDescription: String? {
        switch self {
        case .emptyTurns:
            return "generate_tts_episode requires at least one turn."
        case .notConfigured:
            return "ElevenLabs API key is not configured. Add it in Settings → AI."
        case .emptyAudioData(let index):
            return "TTS synthesis returned no audio for turn \(index)."
        case .storeUnavailable:
            return "AppStateStore is unavailable; cannot publish episode."
        case .snippetNotDownloaded(let episodeID):
            return "Snippet episode \(episodeID) is not downloaded. Download the episode first, then retry generate_tts_episode."
        }
    }
}
