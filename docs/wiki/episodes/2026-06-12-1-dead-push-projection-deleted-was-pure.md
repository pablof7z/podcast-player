---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - podcast-snapshot-projection
  - push-pipeline
  - actor-thread-perf
supersedes: []
related_claims: []
source_lines:
  - 30-57
  - 122-161
  - 3862-3883
captured_at: 2026-06-12T13:58:37Z
---

# Episode: Dead push projection deleted — was pure actor-thread waste

## Prior State

The `register_snapshot_projection_gated("podcast.snapshot")` registration was believed to provide reactive push updates to shells; its comment claimed it 'rides the generic push frame' and had a rev-gated cache for efficiency

## Trigger

Profiling showed 57% CPU in `build_snapshot_payload` → `serde_json::to_string`; investigation revealed (a) the rev counter bumps on every actor tick defeating the cache, and (b) NMP v0.5.0's typed-first Tier-3 encoder discards the generic `KernelSnapshot::projections` map entirely — the registration's multi-MB `from_str`/`clone` output was thrown away

## Decision

Delete the dead `podcast.snapshot` gated projection registration entirely (PR #396). The pull path (`nmp_app_podcast_snapshot`) remains the only functional shell consumption path

## Consequences

- Immediate actor-thread CPU win by removing multi-MB serialization per tick
- Push reactivity was already broken — iOS decode fails on every frame (missing projection key), Android clobbers UI to empty
- The per-domain typed sidecar seam (`register_typed_snapshot_projection`) in v0.5.0 is the correct replacement path

## Open Tail

- iOS and Android must migrate to per-domain sidecar consumption to restore push reactivity

## Evidence

- transcript lines 30-57
- transcript lines 122-161
- transcript lines 3862-3883

