---
type: research-record
date: 2026-06-12
session: 14943b9b-5bf3-4317-bc44-298a773bc75e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/14943b9b-5bf3-4317-bc44-298a773bc75e.jsonl
source_lines: 69391-69429
agent_attribution: ac4a98889b801a45e
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Empirical performance profiling of a 3,615-episode library across 4 scenarios (cold launch, warm mutation, playback, scroll): measured applyKernelState cold 38ms/warm 29ms, recomputeEpisodeProjections 9.6ms nested, hashes off-main at 0.58Hz, confirmed file-stat and triageCounts eliminated"
captured_at: 2026-06-12T12:49:32Z
---

Empirical performance profiling of a 3,615-episode library across 4 scenarios (cold launch, warm mutation, playback, scroll): measured applyKernelState cold 38ms/warm 29ms, recomputeEpisodeProjections 9.6ms nested, hashes off-main at 0.58Hz, confirmed file-stat and triageCounts eliminated

---

User: [Agent task result: Agent "Empirical performance profiling — real library, real measurements" completed]
📋 SUMMARY: Built current main (origin/main dfe3d17f, after fast-forwarding the stale worktree), added print-timing wrappers to the six hot paths, ran a 3,615-episode library on the iOS 26.4 simulator, and captured empirical millisecond measurements across all four scenarios.

🔍 ANALYSIS: The library was already populated with 3,615 episodes across 4 subscriptions (well past the 200+ target), so no seeding was needed. The signpost instrumentation from PR #216 emits to Instruments, not to log durations, so I added temporary `print("[PERF]…")` wrappers and parsed them statistically. The critical correction: many `applyKernelState`/`recompute` fires I first saw were cold-launch settling and discrete content events, NOT per-frame playback. Time-bucketing the confirmed steady-playback window proved the optimizations work.

⚡ ACTIONS: Reconciled worktree to origin/main; instrumented 5 paths (applyKernelState with a toEpisode-call counter, recomputeEpisodeProjections, libraryMetaHash, snapshotContentHash, triageCounts); built/installed/launched on sim EC101638; drove cold launch, show-detail scroll (2,873-ep list), mark-played, and 30s+ playback; parsed logs with a Python script computing mean/p50/p90.

✅ RESULTS — measured numbers, N=3,615 episodes:

```
Operation                  | N items | Mean (ms) | P90 (ms) | Freq/sec      | Thread
---------------------------|---------|-----------|----------|---------------|--------
applyKernelState  (COLD)   | 3615 eps|   38.0    |   42.4   | once @ launch | main
applyKernelState  (WARM)   | 3615 eps|   29.4    |   31.3   | per mutation  | main
recomputeEpisodeProj*      | 3615 eps|    9.6    |   10.4   | per mutation  | main
libraryMetaHash (playback) | 3615 eps|    3.17   |    3.84  | 0.58 Hz       | OFF-main
snapshotContentHash (play) | 3615 eps|    0.78   |    0.79  | 0.58 Hz       | OFF-main
triageCounts               | 3615 eps|   not exercised — never invoked on any flow
toEpisode.fileStat         |  0 calls|    —      |    —     | —             | (removed #219)
```
*recomputeEpisodeProjections runs NESTED inside applyKernelState (verified in code: `applyKernelState` → `performMutationBatch{…invalidateEpisodeProjections()}` → flush → `recomputeEpisodeProjections()`, synchronous). The ~9.6ms is INCLUDED in the ~29ms apply number — the two rows are NOT additive.

📊 STATUS: All four scenarios captured and verified. Worktree has only my 4 temporary instrumentation files changed (uncommitted); they can be reverted with `git checkout` on those paths.

📁 CAPTURE: Worktree at dfe3d17f. Instrumented files: `App/Sources/Bridge/AppStateStore+KernelProjection.swift`, `App/Sources/Bridge/KernelModelHashing.swift`, `App/Sources/Features/Home/HomeView.swift`, `App/Sources/State/AppStateStore+EpisodeProjections.swift`. Store: `…/podcastr-state.v1.episodes.sqlite` (3,615 eps: 2,873 + 498 + 198 + 46). Parsed data: `/tmp/podcastr_capture.log`, `/tmp/podcastr_timed.log`.

➡️ NEXT: The optimization opportunity is WARM `applyKernelState` — it costs ~29ms on EVERY content mutation regardless of how small, because it unconditionally builds a 3,615-entry `priorEpisodesByID` dict and runs the chapters-fallback loop over all 3,615 episodes even when `toEpisode calls=0`. #226 killed per-episode re-mapping but not the O(N) scaffolding around it. Revert instrumentation when done.

📖 STORY EXPLANATION:
1. The inherited worktree was 50 commits behind origin/main and lacked the perf instrumentation the task assumed — I fast-forwarded it to current main (dfe3d17f) so the numbers reflect real shipped code.
2. The simulator already held a genuinely large library — 3,615 episodes across 4 shows — so I measured against that rather than seeding fresh feeds.
3. os_signpost intervals don't surface as durations in log capture, so I added temporary `print("[PERF]…")` timing wrappers, including a `toEpisode` call counter to expose the #226 diff's effectiveness.
4. COLD launch pays ~38ms for the first full projection (toEpisode=3,615, all-new), then ~6 more ~29ms content frames during the metadata-indexer backfill — a sustained burst, not a single hit.
5. The #226 diff works: on every WARM mutation, `toEpisode calls=0` — but `applyKernelState` still costs ~29ms unconditionally from O(N) dict-build and the chapters loop. That is Scenario D's real UI-update cost.
6. Tracing the code proved `recomputeEpisodeProjections` is nested inside `applyKernelState` via the mutation batch, so their times overlap and must not be summed — Scenario D is ~29ms, not ~38ms.
7. During confirmed steady playback (36s window) the hashes fired at only ~0.58 Hz (NOT the assumed 4 Hz) and ran OFF the main thread via #221's `Task.detached`; zero `applyKernelState`/`recompute` fired — main-thread cost from these paths is ~0.
8. `toEpisode.fileStat` is structurally gone (#219 reads cached `fileSizeBytes`), and `triageCounts` never executed on any flow (cached rollup, #224), so both are correctly reported as zero/not-exercised rather than guessed.

🎯 COMPLETED: Captured real Podcastr perf numbers; cold 38ms, warm 29ms, playback near-zero main-thread.
