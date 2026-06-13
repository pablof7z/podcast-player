---
type: episode-card
date: 2026-05-13
session: 9692d124-a1a0-411c-91f9-9d6ebc0b29b1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9692d124-a1a0-411c-91f9-9d6ebc0b29b1.jsonl
salience: product
status: active
subjects:
  - youtube-ingestion
  - agent-skills
  - byok-extractor
supersedes: []
related_claims: []
source_lines:
  - 1-500
captured_at: 2026-06-12T12:21:42Z
---

# Episode: YouTube ingestion skill with BYOK extractor endpoint

## Prior State

No ability for the agent to download YouTube audio as podcast episodes; no YouTube-related tool or skill existed

## Trigger

User requested: 'I want to give the agent the ability of extracting YouTube audio to generate podcast episodes out of it. Skill gated.' Direct InnerTube API approach was considered and rejected due to fragility, App Store risk, and JS signature deciphering requirements.

## Decision

Created a skill-gated `youtube_ingestion` skill using a BYOK (Bring Your Own Key) extractor endpoint pattern. User configures a self-hosted cobalt or yt-dlp wrapper URL in Settings → Providers → YouTube Ingestion. The endpoint contract: POST `{"url": "..."}` → `{"audio_url": "...", "title": "...", "author": "...", "duration_seconds": N}`. Cobalt's `"url"` field name is also accepted. Episodes publish to the Agent Generated podcast with optional transcription.

## Consequences

- Users must self-host an extractor — the app ships no built-in YouTube download capability
- Skill-gated: tools only appear after `use_skill(skill_id: "youtube_ingestion")`
- New protocol `YouTubeIngestionProtocol` + `LiveYouTubeIngestionAdapter` following the existing deps injection pattern
- New files created: YouTubeAudioService.swift, AgentTools+YouTube.swift, YouTubeIngestionSkill.swift, PodcastAgentToolDeps+YouTube.swift, LiveYouTubeIngestionAdapter.swift, YouTubeSettingsView.swift
- Settings domain extended with `youtubeExtractorURL: String?`
- File-length limits forced new adapters into separate files rather than appending to the 644-line LivePodcastAgentToolDeps.swift

## Open Tail

- Search capability requires a custom backend wrapper since cobalt doesn't support search natively

## Evidence

- transcript lines 1-500

