---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - snapshot-transport
  - per-domain-delta
  - kernel-projections
supersedes:
  - 2026-06-06-2-delta-projection-win-b-rejected-not
related_claims: []
source_lines:
  - 30-57
  - 4433-4440
  - 4875-4888
captured_at: 2026-06-12T14:47:13Z
---

# Episode: Full-library snapshot → per-domain delta transport

## Prior State

Every actor-tick command dispatch triggered `emit_now` → `build_snapshot_payload`, which re-serialized the entire podcast library (all podcasts × all episodes) to JSON on the actor thread. 57% of CPU samples were in `serde_json::to_string`, with a 14.6 GB physical footprint from accumulated allocations.

## Trigger

Profiling process 21680 revealed the hot path: every `dispatch_command` → `emit_now` → `make_update` re-serializes the full library. The existing rev-gated cache was defeated because `rev` bumped on essentially every actor tick via `fetch_add(1, Ordering::Relaxed)` scattered across handlers (comments, feed fetch, knowledge, agent notes, etc.).

## Decision

Adopt per-domain typed push sidecars: the kernel emits only the changed domain's projection (playback ~1KB, not a ~3.9MB full-library pull). Individual `PodcastSummary` updates replace the monolithic `PodcastUpdate` envelope per tick. Implemented as kernel domain-projections (#399/#400), tombstone contract (#402), and shell consumption on iOS (#403) and Android (#404).

## Consequences

- ~10x payload reduction on the push path (playback tick applies ~1KB instead of ~3.9MB)
- Revealed that the push path had been completely dead on both shells since NMP v0.3.0 — the perf fix was also a correctness fix
- Shell consumers must handle domain tombstones (null = cleared) and per-domain rev-monotonic drop guards
- Cold-start still uses the full pull path; push is delta-only

## Open Tail

- D — nmp-codegen for `.generated.swift` mirrors (drift gate) still in flight

## Evidence

- transcript lines 30-57
- transcript lines 4433-4440
- transcript lines 4875-4888

