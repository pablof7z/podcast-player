import Foundation

// MARK: - YouTube ingestion tool handler

extension AgentTools {

    static func ingestYouTubeVideoTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let youtubeURL = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !youtubeURL.isEmpty else {
            return toolError("Missing or empty 'url'")
        }
        let customTitle = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let transcribe = (args["transcribe"] as? Bool) ?? true

        do {
            let result = try await deps.youtubeIngestion.ingestVideo(
                youtubeURL: youtubeURL,
                customTitle: customTitle,
                transcribe: transcribe
            )
            var payload: [String: Any] = [
                "episode_id": result.episodeID,
                "title": result.title,
                "author": result.author,
            ]
            if let dur = result.durationSeconds { payload["duration_seconds"] = dur }
            if let ts = result.transcriptStatus { payload["transcript_status"] = ts }
            payload["message"] = transcribe
                ? "YouTube video ingested and transcription queued."
                : "YouTube video ingested."
            return toolSuccess(payload)
        } catch {
            return toolError("ingest_youtube_video failed: \(error.localizedDescription)")
        }
    }
}
