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

    // Internal so AgentTTSComposer+Helpers.swift can access them.
    let ttsClient: ElevenLabsTTSClient
    weak var store: AppStateStore?
    weak var playback: PlaybackState?

    static let logger = Logger.app("AgentTTSComposer")

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
        playNow: Bool,
        generationSource: Episode.GenerationSource? = nil,
        targetPodcastID: UUID? = nil
    ) async throws -> TTSEpisodeResult {
        guard !turns.isEmpty else {
            throw AgentTTSError.emptyTurns
        }
        guard ttsClient.isConfigured else {
            throw AgentTTSError.notConfigured
        }

        // 1. Build BriefingTrack list (one per turn); skips tracks whose audio
        //    fails to load so chapter math stays in sync with tracks.
        let (tracks, trackDurations, survivingTurns) = try await buildTracks(for: turns)

        // 2. Stitch tracks into a single m4a.
        let episodeID = UUID()
        let outputURL = try AgentGeneratedPodcastService.audioFileURL(episodeID: episodeID)
        let durationSeconds = try await BriefingAudioStitcher.stitch(tracks: tracks, outputURL: outputURL)

        // 3. Build chapters and transcript from SURVIVING turns + resolved
        //    durations — uses the filtered list so indices stay aligned.
        let (chapters, transcript) = await buildChaptersAndTranscript(
            turns: survivingTurns,
            trackDurations: trackDurations,
            episodeID: episodeID
        )

        // 3b. Inherit artwork from the first snippet chapter that has one —
        // covers the typical case where the TTS-stitched episode includes
        // clips from a real show, so the result carries that show's image
        // even though the synthetic "Agent Generated" podcast itself has
        // none.
        let inheritedArtwork = chapters.first(where: { $0.imageURL != nil })?.imageURL

        // 4. Register the episode and optionally start playback.
        let episode = await MainActor.run {
            guard let store else { return Optional<Episode>.none }
            return AgentGeneratedPodcastService.publishEpisode(
                title: title,
                description: description ?? "",
                audioURL: outputURL,
                durationSeconds: durationSeconds,
                imageURL: inheritedArtwork,
                generationSource: generationSource,
                targetPodcastID: targetPodcastID,
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

        let podcastID: String
        if let targetPodcastID {
            podcastID = targetPodcastID.uuidString
        } else {
            podcastID = await MainActor.run {
                store?.podcast(feedURL: AgentGeneratedPodcastService.sentinelFeedURL)?.id.uuidString ?? ""
            }
        }

        return TTSEpisodeResult(
            episodeID: episode.id.uuidString,
            podcastID: podcastID,
            title: title,
            durationSeconds: durationSeconds,
            publishedToLibrary: true
        )
    }
}

// MARK: - Audio duration errors

enum AudioDurationError: Error {
    case zeroDuration(URL)
    case assetLoadFailed(URL, underlying: Error)
}

// MARK: - Errors

enum AgentTTSError: LocalizedError {
    case emptyTurns
    case notConfigured
    case emptyAudioData(index: Int)
    case storeUnavailable
    case snippetEpisodeNotFound(episodeID: String)
    case snippetDownloadFailed(episodeID: String, message: String)
    case snippetDownloadTimeout(episodeID: String)
    case noPlayableContent

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
        case .snippetEpisodeNotFound(let episodeID):
            return "Snippet episode \(episodeID) was not found in the library."
        case .snippetDownloadFailed(let episodeID, let message):
            return "Download failed for snippet episode \(episodeID): \(message)"
        case .snippetDownloadTimeout(let episodeID):
            return "Timed out waiting for snippet episode \(episodeID) to download (5 min limit)."
        case .noPlayableContent:
            return "All TTS tracks failed audio loading; nothing to stitch."
        }
    }
}
