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
// Multi-speaker is handled at the turn level: each `.speech` turn specifies its
// own `voiceID`.  A nil `voiceID` falls back to the agent's configured default,
// which is persisted in UserDefaults under `agentDefaultVoiceIDKey`.
//
// The stitcher (BriefingAudioStitcher) takes a flat array of BriefingTrack
// values; only `audioURL`, `startInTrackSeconds`, and `endInTrackSeconds` are
// consumed during the stitch — the remaining metadata fields are inert.

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
        let tracks = try await buildTracks(for: turns)

        // 2. Stitch tracks into a single m4a.
        let episodeID = UUID()
        let outputURL = try AgentGeneratedPodcastService.audioFileURL(episodeID: episodeID)
        let durationSeconds = try await BriefingAudioStitcher.stitch(tracks: tracks, outputURL: outputURL)

        // 3. Register the episode and optionally start playback.
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

        // 4. Optionally start playback.
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

    private func buildTracks(for turns: [TTSTurn]) async throws -> [BriefingTrack] {
        var tracks: [BriefingTrack] = []
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

            case .snippet(let episodeID, let start, let end, let label):
                guard let enclosureURL = await resolveEpisodeAudio(episodeID: episodeID) else {
                    Self.logger.warning("AgentTTSComposer: snippet episode \(episodeID, privacy: .public) not found, skipping")
                    continue
                }
                tracks.append(BriefingTrack(
                    segmentID: dummySegmentID,
                    indexInSegment: index,
                    kind: .quote,
                    audioURL: enclosureURL,
                    startInTrackSeconds: start,
                    endInTrackSeconds: end,
                    transcriptText: label ?? ""
                ))
            }
        }

        return tracks
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
            // Prefer a local download when available; fall back to the remote enclosure.
            if case .downloaded = episode.downloadState {
                let localURL = EpisodeDownloadStore.shared.localFileURL(for: episode)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    return localURL
                }
            }
            return episode.enclosureURL
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
        }
    }
}
