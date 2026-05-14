import Foundation

// MARK: - YouTubeIngestionSkill
//
// Defines the `youtube_ingestion` skill. When activated via
// `use_skill(skill_id: "youtube_ingestion")` the agent receives the manual
// below and gains access to `ingest_youtube_video`.
//
// Requires a user-configured extractor endpoint in Settings → Providers →
// YouTube Ingestion. Without it the tool returns a clear error.

enum YouTubeIngestionSkill {

    static let skill = AgentSkill(
        id: AgentSkillID.youtubeIngestion,
        displayName: "YouTube Ingestion",
        summary: "Download a YouTube video's audio as a podcast episode via a self-hosted extractor, then optionally transcribe it so RAG and wiki tools can reference it.",
        manual: manualText,
        toolNames: [AgentTools.PodcastNames.ingestYouTubeVideo],
        schema: { schemaEntries }
    )

    // MARK: - Manual

    private static let manualText: String = """
    # YouTube Ingestion Skill

    You can download a YouTube video's audio, publish it to the "Agent Generated"
    podcast, and optionally transcribe it — making it searchable via
    `query_transcripts`, summarisable with `summarize_episode`, and usable as
    a snippet in `generate_tts_episode`.

    ## Prerequisites

    The user must have configured a YouTube extractor endpoint in
    Settings → Providers → YouTube Ingestion. Without it `ingest_youtube_video`
    returns an error explaining what to set up. If that happens, tell the user
    what to configure — do not retry.

    ## When to use this

    - The user pastes a YouTube URL and asks you to "add it", "download it",
      or "make a podcast from it".
    - The user wants to transcribe or summarise a YouTube video.
    - The user wants to include a YouTube video's audio as a snippet in a
      generated TTS episode (ingest first, then use the returned episode_id
      in a `generate_tts_episode` snippet turn).

    Skip this skill for tasks that don't end in a library episode.

    ## Tool

    `ingest_youtube_video(url, title?, transcribe?)`

    - `url` (required) — full YouTube URL (youtube.com/watch?v=… or youtu.be/…).
    - `title` (optional) — override the title; defaults to the video's own title.
    - `transcribe` (optional, default true) — whether to start transcription
      immediately after download. Transcription is required before `query_transcripts`
      or `summarize_episode` can work on the episode.

    The tool blocks until download and transcription complete, then returns:
    - `episode_id` — use this in subsequent tool calls.
    - `title`, `author`, `duration_seconds` — episode metadata.
    - `transcript_status` — "ready", "failed", or "queued" (when transcribe=true).
    - `message` — human-readable status line to show the user.

    ## Suggested flow

    1. Call `ingest_youtube_video` with the URL. Pass `transcribe: true` (default)
       unless the user only wants the audio without search capability.
    2. When `transcript_status == "ready"`, you can immediately call
       `query_transcripts`, `summarize_episode`, or start a
       `generate_tts_episode` pipeline with the returned `episode_id`.
    3. When `transcript_status == "failed"`, tell the user — the episode is
       still playable, just not searchable yet.
    """

    // MARK: - Schema

    @MainActor
    private static var schemaEntries: [[String: Any]] {
        [ingestYouTubeVideoSchema]
    }

    private static var ingestYouTubeVideoSchema: [String: Any] {
        functionTool(
            name: AgentTools.PodcastNames.ingestYouTubeVideo,
            description: """
            Download a YouTube video's audio and publish it to the 'Agent Generated' podcast, \
            then optionally transcribe it so it becomes searchable via query_transcripts and \
            summarise_episode. Returns the episode_id for use in subsequent tool calls. \
            Requires a YouTube extractor endpoint configured in Settings → Providers → YouTube Ingestion.
            """,
            properties: [
                "url": ["type": "string", "description": "Full YouTube video URL (youtube.com/watch?v=… or youtu.be/…)."],
                "title": ["type": "string", "description": "Optional title override. Defaults to the video's own title."],
                "transcribe": ["type": "boolean", "description": "Start transcription immediately after download (default: true). Required for query_transcripts and summarize_episode to work on the episode."],
            ],
            required: ["url"]
        )
    }

    // MARK: - Helper

    private static func functionTool(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }
}
