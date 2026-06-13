---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-serialization-perf
  - per-domain-delta
  - slice-local-builders
supersedes:
  - 2026-06-12-1-snapshot-rev-gated-cache-defeated-by
  - 2026-06-13-1-snapshot-cache-defeated-by-per-tick
related_claims: []
source_lines:
  - 30-57
  - 122-161
  - 7954-7971
  - 7977-8003
captured_at: 2026-06-13T02:42:14Z
---

# Episode: Full-library JSON re-serialization on every tick — rev-gated cache defeated by universal rev bumps

## Prior State

build_snapshot_payload had a rev-gated cache believed to make re-serialization cheap — unchanged revs would return a cloned string without rebuilding

## Trigger

CPU profile showed 57% of samples (1,633/2,856) in build_snapshot_payload → serde_json::to_string, plus 14.6 GB physical footprint. Diagnosis revealed rev is bumped by ~7+ handlers on any state change, defeating the cache on essentially every actor tick

## Decision

Replace the monolithic build_podcast_update fan-in with per-domain delta sidecars and slice-local payload builders — each domain emits only its own delta (playback bump emits no library sidecar). The full-library serialization path is eliminated from the hot tick

## Consequences

- Playback tick no longer rebuilds the library/episodes payload
- build_queue_rows_from_store must share an episode_summary helper with the library path for byte-identity (Opus caught a dropped-derivation blocker where per-episode fields were hardcoded to empty)
- Golden fixture alone (empty queue) was insufficient — non-empty-queue regression test added
- Per-domain domain_revs counter now drives reactivity; global snapshot_signal alone is insufficient

## Open Tail

- Remaining non-delta domains still ride the podcast.misc blob; full elimination of whole-library rebuild depends on migrating them

## Evidence

- transcript lines 30-57
- transcript lines 122-161
- transcript lines 7954-7971
- transcript lines 7977-8003

