---
type: episode-card
date: 2026-05-26
session: 14943b9b-5bf3-4317-bc44-298a773bc75e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/14943b9b-5bf3-4317-bc44-298a773bc75e.jsonl
salience: product
status: active
subjects:
  - applykernelstate-fast-path
  - kernel-projection
  - library-generation
supersedes: []
related_claims: []
source_lines:
  - 69467-69514
captured_at: 2026-06-12T12:50:20Z
---

# Episode: Kernel projection generation-counter fast path eliminates 15-18ms no-op ticks

## Prior State

`applyKernelState` unconditionally rebuilt all 3,615 episodes on every kernel tick, including snapshot-only ticks where `library` was byte-identical to the last projection. This cost ~15-18ms per no-op tick (3.4ms dict build + 10.5ms episode reuse loop + 2.5ms chapters fallback) doing zero useful work.

## Trigger

Empirical measurement on 3,615-episode library showed `toEpisode calls=0` on warm ticks yet `applyKernelState` still cost ~15-18ms — the O(N) scaffolding around the diff was the bottleneck.

## Decision

Added O(1) `libraryGeneration` counter to `KernelModel`, bumped atomically on the same line as `library` reassignment in `commitPodcastProjection`. When generation is unchanged, `applyKernelState` routes to `applyKernelSnapshotOnlyState` which projects only settings/last-played/resolved-profiles/now-playing and skips episode rebuild + `invalidateEpisodeProjections()` entirely.

## Consequences

- No-op/snapshot-only ticks: 15-18ms → 0.04ms (measured empirically)
- Full path unchanged at 21-34ms (fires only on real library changes)
- Generation bump is atomically coupled to library reassignment — cannot miss a real change by construction
- `lastProjectedLibraryGeneration` initializes to -1, ensuring cold launch always takes full path

## Open Tail

- `fix/file-size-projection` in-flight branch edits `toEpisode` at its old location — must reconcile against relocated copy in `EpisodeSummary+Projection.swift`

## Evidence

- transcript lines 69467-69514

