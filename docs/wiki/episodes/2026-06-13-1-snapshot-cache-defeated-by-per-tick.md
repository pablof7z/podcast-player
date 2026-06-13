---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-cache
  - podcast-misc-monolith
  - domain-projections
supersedes: []
related_claims: []
source_lines:
  - 30-57
  - 122-161
  - 163-170
captured_at: 2026-06-13T02:30:19Z
---

# Episode: Snapshot cache defeated by per-tick rev bumps — domain-scoped projections required

## Prior State

The rev-gated snapshot cache in build_snapshot_payload was believed to be an effective optimization — an unchanged rev would skip re-serialization.

## Trigger

Profiling showed 57% of CPU (~1633/2856 samples) in build_snapshot_payload → serde_json::to_string, despite the cache. Investigation revealed rev is bumped from many independent sources (comments_handler, feed_fetch, knowledge, agent_note_handler, etc.) on essentially every actor tick, defeating the cache entirely.

## Decision

The monolithic snapshot cache approach is insufficient; domain-scoped projections with independent rev counters are the necessary architecture so that only changed domains are re-serialized per tick.

## Consequences

- Each domain sidecar (podcast.social, etc.) carries its own rev counter and only re-emits when that domain mutates
- The podcast.misc blob must decompose into per-domain sidecars over time
- 14.6 GB physical footprint likely caused by accumulating allocations from repeated full-library serializations

## Open Tail

- The full decomposition of podcast.misc into individual domain sidecars is ongoing

## Evidence

- transcript lines 30-57
- transcript lines 122-161
- transcript lines 163-170

