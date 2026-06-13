---
type: episode-card
date: 2026-05-13
session: 9692d124-a1a0-411c-91f9-9d6ebc0b29b1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9692d124-a1a0-411c-91f9-9d6ebc0b29b1.jsonl
salience: product
status: active
subjects:
  - youtube-ingestion
  - search-youtube
  - agent-tools
supersedes: []
related_claims: []
source_lines:
  - 1082-1280
captured_at: 2026-06-12T12:21:42Z
---

# Episode: Search YouTube tool added to ingestion skill

## Prior State

The youtube_ingestion skill only had `ingest_youtube_video` — users needed to know the exact URL beforehand

## Trigger

User asked: 'can we give the agent a tool to search on youtube too?'

## Decision

Added `search_youtube` tool to the youtube_ingestion skill. Contract: POST `{"search": "query", "limit": N}` to the same extractor URL → `{"results": [{url, title, author, duration_seconds}]}`. Schema defaults: limit=5, max=20. The typical agent flow becomes: search → show list → user picks → ingest.

## Consequences

- Skill now exposes two tools: `search_youtube` and `ingest_youtube_video`
- Search endpoint is a custom extension beyond cobalt's standard API — requires yt-dlp HTTP wrapper or similar
- AgentSkillRegistry, PodcastNames, and dispatchPodcast all updated to include the new tool
- PodcastAgentToolDeps protocol extended with `searchVideos(query:limit:)`

## Open Tail

*(none)*

## Evidence

- transcript lines 1082-1280

