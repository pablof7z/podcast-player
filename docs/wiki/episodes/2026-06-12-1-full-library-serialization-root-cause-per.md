---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - snapshot-projections
  - per-domain-sidecars
  - domain-revs
supersedes: []
related_claims: []
source_lines:
  - 32-57
  - 122-161
  - 3912-3922
  - 4192-4200
captured_at: 2026-06-12T14:08:15Z
---

# Episode: Full-library serialization root cause → per-domain sub-projections

## Prior State

build_snapshot_payload re-serializes the entire library (all podcasts × all episodes) on every actor tick via emit_now. A rev-gated cache existed but was defeated because rev bumped on essentially every command dispatch.

## Trigger

Profiling process 21680 showed 57% of CPU in build_snapshot_payload → serde_json::to_string (lines 32-48). Deeper investigation revealed the rev cache was correct but constantly invalidated (lines 122-161), and the generic push projection's output was entirely discarded by the v0.5.0 typed-first encoder (lines 3912-3913).

## Decision

Adopt per-domain typed sidecars with per-domain revs: only serialize the changed domain (playback tick → ~1KB, not full library). Delete the dead generic podcast.snapshot projection (#396). Wire DomainRevs + bump_domain at every real mutation site (#399/#400).

## Consequences

- Playback tick ships ~1KB delta instead of multi-MB full library
- Global rev still advances on every bump (pull path untouched, golden identical)
- The 10x perf win is architecturally in place but dormant-by-design until shell consumers migrate from full-library pull to per-domain frames
- Dead generic projection removed: immediate actor-thread CPU win (multi-MB from_str/clone per tick eliminated)

## Open Tail

- Swift + Android consumers must migrate to per-domain frames to realize end-to-end perf win

## Evidence

- transcript lines 32-57
- transcript lines 122-161
- transcript lines 3912-3922
- transcript lines 4192-4200

