import Foundation

// MARK: - YouTubeIngestionProtocol
//
// Abstracts the full YouTube-video → library-episode pipeline so the tool
// handler in `AgentTools+YouTube.swift` stays testable without live services.
//
// The live adapter (`LiveYouTubeIngestionAdapter`) calls:
//   1. `YouTubeAudioService` to resolve the audio stream URL + metadata.
//   2. `URLSession` to download the audio to the agent-episodes directory.
//   3. `AgentGeneratedPodcastService.publishEpisode` to register the episode.
//   4. Optionally `TranscriptIngestService` to kick off transcription.

public protocol YouTubeIngestionProtocol: Sendable {
    func ingestVideo(
        youtubeURL: String,
        customTitle: String?,
        transcribe: Bool
    ) async throws -> YouTubeIngestionResult
}

// MARK: - Result

public struct YouTubeIngestionResult: Sendable {
    public let episodeID: String
    public let title: String
    public let author: String
    public let durationSeconds: TimeInterval?
    public let transcriptStatus: String?

    public init(
        episodeID: String,
        title: String,
        author: String,
        durationSeconds: TimeInterval?,
        transcriptStatus: String?
    ) {
        self.episodeID = episodeID
        self.title = title
        self.author = author
        self.durationSeconds = durationSeconds
        self.transcriptStatus = transcriptStatus
    }
}
