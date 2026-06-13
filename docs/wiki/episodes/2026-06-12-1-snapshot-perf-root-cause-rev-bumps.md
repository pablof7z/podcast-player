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
  - build-snapshot-payload
supersedes:
  - 2026-06-12-1-rev-gated-snapshot-cache-defeated-on
related_claims: []
source_lines:
  - 30-57
  - 99-120
  - 134-154
  - 161-170
captured_at: 2026-06-12T12:24:35Z
---

# Episode: Snapshot perf root cause: rev bumps from ~10 sites defeat the rev-gated cache

## Prior State

The code comment claimed build_snapshot_payload had a 'rev-gated snapshot-string cache' making unchanged ticks cheap — the assumption was that the cache was effective and the perf problem lay elsewhere

## Trigger

Process profile showed 57% of CPU in build_snapshot_payload → serde_json::to_string despite the cache; investigation revealed rev is bumped by ~10 independent sites (comments_handler, feed_fetch, knowledge, agent_note_handler, etc.) on essentially every actor tick, giving near-zero cache hit rate

## Decision

The root problem is not a broken cache but that the granularity of change-tracking is too coarse — any change anywhere in the entire podcast domain forces a full-library re-serialization. The fix must reduce what gets serialized per tick (domain sub-projections), not improve caching

## Consequences

- Domain sub-projections (per-domain revs + typed sidecars) became the headline architecture item, replacing any cache-tuning approach
- The 14.6 GB physical footprint is likely from accumulating allocations from repeated full-library serializations
- String escaping (format_escaped_str) is the leaf hotspot but serde is just doing its job on a huge payload — real fix is reducing payload size per tick

## Open Tail

- Per-domain bump_domain wiring at real mutation sites (PR #399 sent back for completion)

## Evidence

- transcript lines 30-57
- transcript lines 99-120
- transcript lines 134-154
- transcript lines 161-170

