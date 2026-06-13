---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - dead-projection
  - podcast-snapshot-gate
  - nmp-tier3-encoder
supersedes: []
related_claims: []
source_lines:
  - 3803-3827
  - 3868-3883
  - 4192-4196
captured_at: 2026-06-12T12:24:35Z
---

# Episode: Dead projection discovery: gated podcast.snapshot output discarded by v0.5.0 encoder

## Prior State

The register_snapshot_projection_gated('podcast.snapshot', …) block in register.rs was believed to be the correct seam for reactive push delivery of podcast state — it was explicitly optimized with a rev gate (upstream PR #1068) and its comment said state 'rides the generic push frame'

## Trigger

Fable planner investigation + independent verification: NMP v0.5.0's Tier-3 encoder (ADR-0044/PR-B) encodes ONLY the typed envelope + typed-projection FlatBuffer sidecars, discarding the generic KernelSnapshot::projections map entirely; every real consumer (iOS, Android, harness, TUI) uses the pull symbol nmp_app_podcast_snapshot, not the registered projection

## Decision

Delete the entire register_snapshot_projection_gated('podcast.snapshot') block — it is pure actor-thread waste (multi-MB from_str on rev change, multi-MB Value::clone on unchanged ticks, output discarded by encoder). PR #396 merged

## Consequences

- Immediate actor-thread CPU win by removing the dead multi-MB serialization on every emit tick
- The push projection path for podcast state is now exclusively the typed sidecar seam (register_typed_snapshot_projection), not the generic JSON projection path
- Prior work optimizing the gated projection (upstream #1068) is now historical — it optimized a path that produces no output

## Open Tail

*(none)*

## Evidence

- transcript lines 3803-3827
- transcript lines 3868-3883
- transcript lines 4192-4196

