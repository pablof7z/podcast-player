import Foundation

// MARK: - Podcast tool schema (OpenAI tool format)
//
// This file declares the OpenAI-compatible JSON-schema entries for every
// podcast-domain tool the agent can call. The orchestrator concatenates this
// array onto `AgentTools.schema` at merge time:
//
//     let allTools = AgentTools.schema + AgentTools.podcastSchema
//
// Adding a new podcast tool requires four steps, in order:
//   1. Add the canonical name to `AgentTools.PodcastNames`
//      in `AgentTools+Podcast.swift`.
//   2. Add a `tool(...)` entry below.
//   3. Add a `case` in `AgentTools.dispatchPodcast(...)`.
//   4. Add a unit test in `AgentToolsPodcastTests.swift`.

extension AgentTools {

    /// OpenAI-compatible tool schema array for the podcast tool surface.
    ///
    /// Kept as a separate computed property (not merged into `AgentTools.schema`)
    /// so the existing template tests continue to assert against the original
    /// schema unchanged.
    @MainActor
    static var podcastSchema: [[String: Any]] {
        [
            podcastTool(
                name: PodcastNames.playEpisodeAt,
                description: "Open the podcast player at a specific episode and timestamp. Use this when the user says 'play that part where…' or asks to jump to a specific moment they remember.",
                properties: [
                    "episode_id": ["type": "string", "description": "The episode's stable ID (UUID or canonical string)."],
                    "timestamp": ["type": "number", "description": "Position to seek to, in seconds from the start of the episode. Use 0 to play from the beginning."],
                ],
                required: ["episode_id", "timestamp"]
            ),
            podcastTool(
                name: PodcastNames.pausePlayback,
                description: "Pause the current podcast playback and persist the playhead. Use when the user asks you to stop or pause.",
                properties: [:],
                required: []
            ),
            podcastTool(
                name: PodcastNames.setPlaybackRate,
                description: "Set the active playback speed. Use when the user asks to listen faster or slower.",
                properties: [
                    "rate": ["type": "number", "description": "Requested playback speed multiplier. The player supports roughly 0.5x to 3.0x."],
                ],
                required: ["rate"]
            ),
            podcastTool(
                name: PodcastNames.setSleepTimer,
                description: "Arm or clear the sleep timer. Use for requests like 'stop after 30 minutes' or 'pause at the end of this episode'.",
                properties: [
                    "mode": ["type": "string", "enum": ["off", "minutes", "end_of_episode"], "description": "Timer mode."],
                    "minutes": ["type": "integer", "description": "Duration in minutes when mode is 'minutes'. Max 180."],
                ],
                required: ["mode"]
            ),
            podcastTool(
                name: PodcastNames.searchEpisodes,
                description: "Semantic + keyword search across the user's subscribed podcasts. Use for fuzzy recall like 'the one about stamps last week' or topical queries like 'episodes on Zone 2 training'.",
                properties: [
                    "query": ["type": "string", "description": "Natural-language query."],
                    "scope": ["type": "string", "description": "Optional podcast ID to constrain the search to one show."],
                    "limit": ["type": "integer", "description": "Maximum results (1–25). Defaults to 10."],
                ],
                required: ["query"]
            ),
            podcastTool(
                name: PodcastNames.queryWiki,
                description: "Look up a topic in the LLM-generated podcast wiki. Use this for definitional questions ('what is Zone 2?') or to surface cross-episode context the user has already built up.",
                properties: [
                    "topic": ["type": "string", "description": "Topic, person, place, or concept to look up."],
                    "scope": ["type": "string", "description": "Optional podcast ID to constrain the wiki lookup to one show's wiki."],
                    "limit": ["type": "integer", "description": "Maximum pages returned (1–10). Defaults to 5."],
                ],
                required: ["topic"]
            ),
            podcastTool(
                name: PodcastNames.queryTranscripts,
                description: "RAG search over transcript chunks. Returns timestamped excerpts with speaker labels. Use this when the user asks 'what did they say about X?' and you need direct quotes to ground the answer.",
                properties: [
                    "query": ["type": "string", "description": "Natural-language question."],
                    "scope": ["type": "string", "description": "Optional scope: an episode_id, a podcast_id, or omit for all-corpus search."],
                    "limit": ["type": "integer", "description": "Maximum chunks returned (1–25). Defaults to 8."],
                ],
                required: ["query"]
            ),
            podcastTool(
                name: PodcastNames.generateBriefing,
                description: "Compose a personalized TLDR audio briefing across episodes. Use when the user asks 'catch me up on this week' or wants a synthesized digest. Returns a briefing handle the user can play.",
                properties: [
                    "scope": ["type": "string", "description": "Selection scope: 'this_week', 'unlistened', a podcast_id, or a custom keyword."],
                    "length": ["type": "integer", "description": "Target length in minutes (3–30)."],
                    "style": ["type": "string", "enum": ["news", "deep_dive", "quick_hits"], "description": "Optional style hint."],
                ],
                required: ["scope", "length"]
            ),
            podcastTool(
                name: PodcastNames.perplexitySearch,
                description: "Run an online web search via Perplexity for facts that are NOT in the user's podcast corpus. Use for current events, fact-checks, citation lookups, or contrarian-take queries.",
                properties: [
                    "query": ["type": "string", "description": "Question to send to Perplexity."],
                ],
                required: ["query"]
            ),
            podcastTool(
                name: PodcastNames.summarizeEpisode,
                description: "Generate an on-demand summary of a single episode. Use when the user asks 'TLDR this' or 'what's this episode about?' for a specific episode.",
                properties: [
                    "episode_id": ["type": "string", "description": "The episode to summarize."],
                    "length": ["type": "string", "enum": ["short", "medium", "long"], "description": "Optional summary length. Defaults to 'medium'."],
                ],
                required: ["episode_id"]
            ),
            podcastTool(
                name: PodcastNames.findSimilarEpisodes,
                description: "Discovery — find episodes semantically similar to a seed episode. Use when the user says 'more like this' or 'what else should I listen to after this?'.",
                properties: [
                    "seed_episode_id": ["type": "string", "description": "The episode to use as a similarity seed."],
                    "k": ["type": "integer", "description": "Number of similar episodes to return (1–20). Defaults to 5."],
                ],
                required: ["seed_episode_id"]
            ),
            podcastTool(
                name: PodcastNames.markEpisodePlayed,
                description: "Mark an episode as played. Use only when the user explicitly asks to mark something listened/done.",
                properties: [
                    "episode_id": ["type": "string", "description": "The episode to mark played."],
                ],
                required: ["episode_id"]
            ),
            podcastTool(
                name: PodcastNames.markEpisodeUnplayed,
                description: "Mark an episode as unplayed. Use when the user says they have not listened yet or wants to undo a played mark.",
                properties: [
                    "episode_id": ["type": "string", "description": "The episode to mark unplayed."],
                ],
                required: ["episode_id"]
            ),
            podcastTool(
                name: PodcastNames.downloadEpisode,
                description: "Download an episode's audio for offline playback. Use when the user asks to save or download an episode.",
                properties: [
                    "episode_id": ["type": "string", "description": "The episode to download."],
                ],
                required: ["episode_id"]
            ),
            podcastTool(
                name: PodcastNames.requestTranscription,
                description: "Request transcript ingestion for an episode, using publisher transcripts first and the configured STT provider when needed.",
                properties: [
                    "episode_id": ["type": "string", "description": "The episode to transcribe/index."],
                ],
                required: ["episode_id"]
            ),
            podcastTool(
                name: PodcastNames.refreshFeed,
                description: "Refresh a subscribed podcast feed and ingest newly published episodes. Use when the user asks for the latest from one show.",
                properties: [
                    "podcast_id": ["type": "string", "description": "The subscribed podcast/feed ID to refresh."],
                ],
                required: ["podcast_id"]
            ),
            podcastTool(
                name: PodcastNames.openScreen,
                description: "Navigate the app UI to a named route (e.g. 'library', 'now_playing', 'briefings', 'wiki/zone-2'). Use sparingly — only when the user explicitly asks to go somewhere.",
                properties: [
                    "route": ["type": "string", "description": "App route string."],
                ],
                required: ["route"]
            ),
            podcastTool(
                name: PodcastNames.setNowPlaying,
                description: "Update the player's now-playing context without necessarily starting playback (preload artwork, seed the lock-screen). Use as a setup step before a 'play_episode_at' or to reflect what the agent is currently grounded in.",
                properties: [
                    "episode_id": ["type": "string", "description": "Episode to mark as now playing."],
                    "timestamp": ["type": "number", "description": "Optional timestamp in seconds. Omit to leave position unchanged."],
                ],
                required: ["episode_id"]
            ),
            podcastTool(
                name: PodcastNames.delegate,
                description: "TENEX-compatible async delegation. Send a task with full context to another agent or team, then stop for the turn until delegated work completes.",
                properties: [
                    "recipient": ["type": "string", "description": "Recipient agent slug, team name, or Nostr pubkey."],
                    "prompt": ["type": "string", "description": "The delegated task plus all context the recipient needs."],
                ],
                required: ["recipient", "prompt"]
            ),
            podcastTool(
                name: PodcastNames.listSubscriptions,
                description: "List the podcasts the user is currently subscribed to, sorted by title. Use this before offering to unsubscribe or when the user asks 'what am I subscribed to?'. Returns each show's id, title, total + unplayed episode counts, and last-published date.",
                properties: [
                    "limit": ["type": "integer", "description": "Maximum subscriptions to return. Defaults to 25, capped at 100."],
                ],
                required: []
            ),
            podcastTool(
                name: PodcastNames.listCategories,
                description: "List the LLM-generated podcast categories in the user's library. Use this before answering category-management questions or before moving a show between categories.",
                properties: [
                    "limit": ["type": "integer", "description": "Maximum categories to return. Defaults to 25, capped at 100."],
                    "include_podcasts": ["type": "boolean", "description": "Whether to include compact podcast rows under each category. Defaults to true."],
                ],
                required: []
            ),
            podcastTool(
                name: PodcastNames.changePodcastCategory,
                description: "Move a subscribed podcast into an existing generated category. Use only after identifying the target category by list_categories or from the user's explicit wording.",
                properties: [
                    "podcast_id": ["type": "string", "description": "The subscribed podcast/feed ID to move."],
                    "category_id": ["type": "string", "description": "Preferred target category UUID from list_categories."],
                    "category_slug": ["type": "string", "description": "Alternative target category slug when the UUID is unavailable."],
                    "category_name": ["type": "string", "description": "Alternative target category display name when the UUID or slug is unavailable."],
                ],
                required: ["podcast_id"]
            ),
            podcastTool(
                name: PodcastNames.listEpisodes,
                description: "List episodes of a specific podcast, newest first. Use after list_subscriptions when the user wants to drill into one show. Returns played/unplayed state and current playback position for each episode.",
                properties: [
                    "podcast_id": ["type": "string", "description": "The subscribed podcast/feed ID to list episodes for."],
                    "limit": ["type": "integer", "description": "Maximum episodes to return. Defaults to 25, capped at 100."],
                ],
                required: ["podcast_id"]
            ),
            podcastTool(
                name: PodcastNames.listInProgress,
                description: "List episodes the user has started but not finished, newest first. Use to answer 'what was I listening to?' or 'what should I resume?' without spending a search call.",
                properties: [
                    "limit": ["type": "integer", "description": "Maximum episodes to return. Defaults to 25, capped at 100."],
                ],
                required: []
            ),
            podcastTool(
                name: PodcastNames.listRecentUnplayed,
                description: "List recently published episodes the user hasn't played, newest first. Mirrors the Today tab's New Episodes feed. Use to answer 'what's new?' or 'what should I listen to next?'.",
                properties: [
                    "limit": ["type": "integer", "description": "Maximum episodes to return. Defaults to 25, capped at 100."],
                ],
                required: []
            ),
            podcastTool(
                name: PodcastNames.createClip,
                description: "Save a clip of an episode on behalf of the user — creates a timestamped excerpt that appears in the user's Clippings tab. Use when the user says 'clip that', 'save that part', or asks you to bookmark a moment. Always confirm the start/end range with the user before clipping unless they were explicit. Prefer supplying transcript_text when you already have it from query_transcripts.",
                properties: [
                    "episode_id": ["type": "string", "description": "The episode to clip (UUID string)."],
                    "start_seconds": ["type": "number", "description": "Clip start time in seconds from the episode origin."],
                    "end_seconds": ["type": "number", "description": "Clip end time in seconds from the episode origin."],
                    "caption": ["type": "string", "description": "Optional user-visible headline for the clip."],
                    "transcript_text": ["type": "string", "description": "Verbatim transcript text for the clipped span. Supply this when you have it from a prior query_transcripts call so it doesn't need to be re-fetched."],
                ],
                required: ["episode_id", "start_seconds", "end_seconds"]
            ),
            podcastTool(
                name: PodcastNames.downloadAndTranscribe,
                description: """
                Download an episode for offline playback AND await the full transcription pipeline \
                before returning. Blocks until the transcript is ready (or fails). \
                Use this when you need the transcript to be available immediately after the call \
                — for example before calling query_transcripts on a fresh episode. \
                Prefer this over separate download_episode + request_transcription calls when the \
                goal is to have the transcript ready to query in the same turn.
                """,
                properties: [
                    "episode_id": ["type": "string", "description": "The episode to download and transcribe (UUID string)."],
                ],
                required: ["episode_id"]
            ),
            podcastTool(
                name: PodcastNames.queueEpisodeSegments,
                description: """
                Load one or more time-bounded segments from an episode (or multiple episodes) into the Up Next queue, \
                then optionally start playing the first segment immediately. \
                Use when the user says 'play section X then Y from episode Z', 'play the intro and the interview part', \
                or asks to queue specific chapters. \
                Before calling this tool, use query_transcripts or the episode's chapter list to resolve the \
                timestamps for each section the user named. \
                Each segment plays from start_seconds to end_seconds; when it ends, a subtle sound cue fires and \
                the next segment starts automatically. \
                Distinct from play_episode_at (which jumps to a single timestamp with no end boundary) — \
                use this tool any time two or more bounded segments need to play in sequence.
                """,
                properties: [
                    "segments": [
                        "type": "array",
                        "description": "Ordered list of segments to enqueue. Must contain at least one entry.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "episode_id": ["type": "string", "description": "UUID of the episode containing this segment."],
                                "start_seconds": ["type": "number", "description": "Seconds from the episode origin where this segment begins."],
                                "end_seconds": ["type": "number", "description": "Seconds from the episode origin where this segment ends."],
                                "label": ["type": "string", "description": "Optional human-readable label (e.g. chapter title) shown in the queue sheet."],
                            ] as [String: Any],
                            "required": ["episode_id", "start_seconds", "end_seconds"],
                        ] as [String: Any],
                    ] as [String: Any],
                    "play_now": ["type": "boolean", "description": "If true, start playing the first segment immediately and push the rest into the queue. If false, append all segments to the queue without starting playback. Defaults to true."],
                ],
                required: ["segments"]
            ),
            podcastTool(
                name: PodcastNames.generateTTSEpisode,
                description: """
                Synthesise a custom audio episode using ElevenLabs TTS and/or original episode snippets, \
                then publish it to the 'Agent Generated' podcast so the user can play it like any other episode. \
                Use for requests like 'make me a TLDR of the ADHD stuff', 'create a fake podcast interview', \
                or 'summarise X with snippets from Y and Z'. \
                Turns are ordered: each turn is either a 'speech' turn (text → TTS with a specific voice) \
                or a 'snippet' turn (an original audio clip from an existing episode). \
                For multi-speaker dialogue, alternate speech turns with different voice_id values. \
                You can use ElevenLabs emotion cues in text like '[cheerfully]', '[excitedly]', '[laughs]'. \
                For snippet turns, resolve episode IDs and timestamps via query_transcripts first.
                """,
                properties: [
                    "title": ["type": "string", "description": "Episode title shown in the library."],
                    "description": ["type": "string", "description": "Short episode description (plain text)."],
                    "turns": [
                        "type": "array",
                        "description": "Ordered sequence of turns that make up the episode. Must contain at least one entry.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "kind": ["type": "string", "enum": ["speech", "snippet"], "description": "'speech' for TTS narration, 'snippet' for an original-audio excerpt from an existing episode."],
                                "text": ["type": "string", "description": "Text to synthesise. Required when kind='speech'. Supports ElevenLabs emotion markers like [cheerfully]."],
                                "voice_id": ["type": "string", "description": "ElevenLabs voice ID for this speech turn. Omit to use the agent's configured default voice."],
                                "episode_id": ["type": "string", "description": "UUID of the source episode. Required when kind='snippet'."],
                                "start_seconds": ["type": "number", "description": "Start of the audio excerpt in seconds. Required when kind='snippet'."],
                                "end_seconds": ["type": "number", "description": "End of the audio excerpt in seconds. Required when kind='snippet'."],
                                "label": ["type": "string", "description": "Optional label for a snippet turn (e.g. speaker name or topic)."],
                            ] as [String: Any],
                            "required": ["kind"],
                        ] as [String: Any],
                    ] as [String: Any],
                    "play_now": ["type": "boolean", "description": "If true, immediately start playing the finished episode. Defaults to false."],
                ],
                required: ["title", "turns"]
            ),
            podcastTool(
                name: PodcastNames.configureAgentVoice,
                description: """
                Set the agent's default ElevenLabs voice ID. Future 'generate_tts_episode' speech turns \
                that omit 'voice_id' will use this voice. \
                Use when the user says 'use a different voice', 'sound like X', or explicitly picks a voice \
                from the ElevenLabs voice list. Always confirm the voice_id exists in the user's ElevenLabs \
                account before setting.
                """,
                properties: [
                    "voice_id": ["type": "string", "description": "ElevenLabs voice ID to set as the agent's default."],
                ],
                required: ["voice_id"]
            ),
        ]
    }

    /// Local copy of the OpenAI function-tool builder. The base file's helper
    /// is `private`, so we duplicate the (tiny) shape here to keep this lane
    /// self-contained.
    private static func podcastTool(
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
