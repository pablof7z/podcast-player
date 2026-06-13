---
type: episode-card
date: 2026-06-03
session: 55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1.jsonl
salience: root-cause
status: active
subjects:
  - carplay
  - chapters
  - store-projection
supersedes: []
related_claims: []
source_lines:
  - 1140-1176
captured_at: 2026-06-12T13:11:23Z
---

# Episode: CarPlay chapters resolved from stale snapshot

## Prior State

CarPlayNowPlaying read chapters from PlaybackState.episode — a value snapshot taken at load time. When chapters hydrated later (AI generation) or before CarPlay connected, that snapshot reported zero chapters, so the chapter button and list never appeared.

## Trigger

Explicit task. A second defect also found: the scene-delegate poll tracked only episode ID, so chapters arriving on an already-loaded episode never triggered a refresh.

## Decision

Added CarPlayNowPlaying.navigableChapters(playback:store:) that resolves chapters from store.episodes (the always-current Rust projection) by ID. Routed both read sites (button visibility + chapter list) through it. Changed the poll tracker to (episodeID, navigableChapterCount) so late chapter arrivals fire exactly one refresh.

## Consequences

- CarPlay chapter list appears as soon as chapters are ready, regardless of timing
- AI-generated chapters that arrive after initial load now trigger a UI refresh
- Both CarPlay read paths (button + list) use one shared resolver — no divergence

## Open Tail

*(none)*

## Evidence

- transcript lines 1140-1176

