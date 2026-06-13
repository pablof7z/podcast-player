---
type: research-record
date: 2026-06-12
session: 14943b9b-5bf3-4317-bc44-298a773bc75e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/14943b9b-5bf3-4317-bc44-298a773bc75e.jsonl
source_lines: 69467-69513
agent_attribution: a6dd46c3844221cc9
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Investigation of warm applyKernelState cost: empirically established no-op ticks cost 15-18ms from O(N) dict-build + chapters loop with toEpisode calls=0; fixed with O(1) generation counter fast-path reducing to 0.04ms"
captured_at: 2026-06-12T12:49:32Z
---

Investigation of warm applyKernelState cost: empirically established no-op ticks cost 15-18ms from O(N) dict-build + chapters loop with toEpisode calls=0; fixed with O(1) generation counter fast-path reducing to 0.04ms

---

User: [Agent task result: Agent "Fix warm applyKernelState O(N) dict+chapters loop" completed]
The work is complete and durable. Here is my final report.

## Summary

Fixed the warm `applyKernelState` cost in PR **#228** (`fix/apply-kernel-fast-path`).

## What was actually happening (investigation findings)

The task's premise was correct but its framing of *which tick* was conflated. Through measured instrumentation on the 3,615-episode sim fixture, I established:

- `applyKernelState`'s observation arms on `kernel.library` **+** `podcastSnapshot` **+** `kernelIdentity`. It fires on snapshot/identity-only ticks where `library` is byte-identical to the last projection.
- On those ticks, the full pass cost **~15–18ms** (dict build ~3.4ms + episode reuse loop ~10.5ms + chapters fallback ~2.5ms) doing **zero useful work** — `changed=0, new=0, removed=0, toEpisode=0`, reproducing `self.episodes` element-for-element. This is exactly the task's `toEpisode calls=0` root cause.
- A key empirical finding: manual **mark-played / star** in this build are served by an *optimistic Swift write* (`markEpisodePlayed` writes `self.episodes` directly) plus a fast-path tick — the kernel echo does not re-fire a distinct gen-advancing projection here. So I did **not** claim "mark-played 29ms→0"; the defensible measured win is the no-op tick class.

## The fix

- New O(1) `KernelModel.libraryGeneration`, bumped on the same line that reassigns `library` in `commitPodcastProjection` (atomically coupled — cannot miss a real change).
- When the generation is unchanged, `applyKernelState` routes to a new `applyKernelSnapshotOnlyState` that projects only settings/last-played/resolved-profiles/now-playing and skips the episode rebuild + `invalidateEpisodeProjections()`.
- Chose the O(1) generation counter over the task's suggested per-field `zip` scan (which is itself O(N)).

**Measured result:** no-op / snapshot-only tick **~15–18ms → ~0.04ms**; full path unchanged (~21–34ms, fires only on real library changes).

## Validation

- 49 tests passed (`AppStateStorePerformanceTests`, `EpisodePlayedStateTests`, `HomeDerivedEpisodesTests`, `EpisodeSummaryTests`, `StarredEpisodeTests`).
- Build + launch: full path renders all podcasts/episodes correctly; fast-path verified at 0.04ms via runtime instrumentation (since removed).
- No Rust source change.

## Files

- `/Users/pablofernandez/Work/podcast-player/.claude/worktrees/agent-a6dd46c3844221cc9/App/Sources/Bridge/AppStateStore+KernelProjection.swift` — fast-path branch + `applyKernelSnapshotOnlyState` + `projectSnapshotDerivedState` (now 472 lines, under the 500 limit)
- `/Users/pablofernandez/Work/podcast-player/.claude/worktrees/agent-a6dd46c3844221cc9/App/Sources/Bridge/KernelModel.swift` — `libraryGeneration` counter + bump
- `/Users/pablofernandez/Work/podcast-player/.claude/worktrees/agent-a6dd46c3844221cc9/App/Sources/Bridge/EpisodeSummary+Projection.swift` (new — extracted mapping)
- `/Users/pablofernandez/Work/podcast-player/.claude/worktrees/agent-a6dd46c3844221cc9/App/Sources/Bridge/AppStateStore+SyntheticBackfill.swift` (new — extracted backfill)

## Line-limit note

The projection file was already a tracked hard-limit violation (606 lines on main; `kernelprojection-split` backlog). I performed the backlog's named extractions to bring it to 472. `KernelModel.swift` grew 516→527 (pre-existing over-limit, flagged).

## Follow-up flagged in the PR

`fix/file-size-projection` (in-flight) edits `toEpisode`'s download-size block at its old location — reconcile against the relocated copy in `EpisodeSummary+Projection.swift` when it lands.

PR: https://github.com/pablof7z/podcast-player/pull/228

One note: I could not reproduce an in-session generation advance (gen=2) without a network-dependent subscribe/refresh; the full-path correctness rests on the cold-launch full build (rendering all 3,615 episodes correctly) plus the structural proof that the generation bump is on the same statement as the `library` reassignment. The WIP.md entry was added at the base-dir path (not committed, per AGENTS.md).
