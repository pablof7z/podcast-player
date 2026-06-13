---
type: episode-card
date: 2026-05-10
session: c6722edd-ee95-4534-9e81-9bb6b5dc60d6
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c6722edd-ee95-4534-9e81-9bb6b5dc60d6.jsonl
salience: root-cause
status: active
subjects:
  - ad-skip-stale-cache
  - playback-state
  - ai-chapter-compiler
  - live-data-bridge
supersedes: []
related_claims: []
source_lines:
  - 3448-3452
  - 3607-3623
  - 3838-3838
captured_at: 2026-06-12T11:50:37Z
---

# Episode: Preexisting ad-skip-after-detect bug surfaced and resolution bundled

## Prior State

`PlaybackState.adSegments` is set only in `setEpisode` (line 248). When `AIChapterCompiler.compileIfNeeded` finishes mid-session and writes to the store, `PlaybackState`'s local cache is never refreshed — ads detected during playback are dead until next episode load.

## Trigger

Planning agent discovered this bug while designing the intro/outro reactive bridge and realized the new markers would inherit the same staleness

## Decision

Fix bundled into commit 5d via a `RootView` `.onChange(of: store.episode(id:))` reactive bridge that pushes both `adSegments` and intro/outro markers into `PlaybackState` when the live episode model changes

## Consequences

- Both ad-skip and intro/outro will work correctly when detection completes during playback
- Existing ad-skip behavior improves for all users — a free UX win bundled into this feature batch
- User chose to bundle the fix into commit 5d rather than splitting into its own micro-commit

## Open Tail

*(none)*

## Evidence

- transcript lines 3448-3452
- transcript lines 3607-3623
- transcript lines 3838-3838

