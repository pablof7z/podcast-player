---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-perf
  - rev-cache-defeat
  - full-library-serialization
supersedes: []
related_claims: []
source_lines:
  - 30-57
  - 122-161
captured_at: 2026-06-12T11:45:46Z
---

# Episode: Rev-gated snapshot cache defeated on every actor tick

## Prior State

The rev-gated snapshot cache in `build_snapshot_payload` was believed to prevent redundant re-serialization — the code comment claims it provides a cheap clone path when rev is unchanged.

## Trigger

CPU sample of process 21680 showed 57% of samples (~1633/2856) in `build_snapshot_payload` → `serde_json::to_string`, plus a 14.6 GB physical footprint from accumulated allocations. Investigation revealed `rev.fetch_add(1, Ordering::Relaxed)` is called from dozens of handlers on every command dispatch, bumping rev on essentially every tick and defeating the cache.

## Decision

The performance problem is not a serialization optimization issue but a structural one: full-library re-serialization on any state change is fundamentally unscalable. The fix must reduce what gets serialized per tick (delta snapshots or per-domain gated projections), not optimize the serialization itself.

## Consequences

- The string-escaping leaf bottleneck (`format_escaped_str`) is a symptom, not the root cause
- 14.6 GB memory footprint is likely from repeated full-library allocation on every tick
- Any per-domain or delta approach must bypass the global-rev invalidation pattern

## Open Tail

- Per-domain rev architecture must ensure domain-local bumps don't cause global rev churn

## Evidence

- transcript lines 30-57
- transcript lines 122-161

