---
type: episode-card
date: 2026-05-26
session: 14943b9b-5bf3-4317-bc44-298a773bc75e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/14943b9b-5bf3-4317-bc44-298a773bc75e.jsonl
salience: root-cause
status: active
subjects:
  - episode-diff-level
  - applykernelstate
  - toepisode
supersedes: []
related_claims: []
source_lines:
  - 69182-69221
captured_at: 2026-06-12T12:50:20Z
---

# Episode: Episode-level diff is wrong — must diff at EpisodeSummary level

## Prior State

Task proposed Episode-level diff (adding `Equatable` to `Episode`) to avoid per-tick re-mapping all N episodes through `toEpisode()`.

## Trigger

Investigation confirmed that an Episode-level diff is a near-no-op: it still calls `toEpisode` for all N summaries to produce the comparison value, doing the same work it purports to avoid. The real saving requires diffing at the cheaper `EpisodeSummary` level (already `Equatable`) and only calling `toEpisode` for changed/new summaries.

## Decision

Diff at `EpisodeSummary` level, not `Episode` level. Only map new/changed summaries through `toEpisode`. Reuse prior `Episode` objects when their summary is unchanged.

## Consequences

- `toEpisode` calls drop to only changed episodes on warm ticks (empirically confirmed: toEpisode calls=0 on most warm ticks)
- But O(N) dict-build + chapters fallback still remained as a separate bottleneck (addressed by generation-counter fast path in PR #228)
- Audit of all `state.episodes` writers confirmed reuse is safe: each dispatches to kernel, is chapters, or converges to toEpisode's value

## Open Tail

*(none)*

## Evidence

- transcript lines 69182-69221

