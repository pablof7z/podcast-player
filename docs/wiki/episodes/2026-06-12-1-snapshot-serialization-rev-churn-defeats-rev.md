---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - nmp-app-podcast-snapshot-serialization
  - build-snapshot-payload-perf
  - podcast-handle-rev
supersedes: []
related_claims: []
source_lines:
  - 30-57
  - 122-170
captured_at: 2026-06-12T21:45:00Z
---

# Episode: Snapshot serialization: rev-churn defeats rev-gated cache

## Prior State

The register.rs comment claimed build_snapshot_payload had a rev-gated snapshot-string cache providing a cheap path for unchanged revisions, so the assumption was that re-serialization was avoided unless data actually changed

## Trigger

CPU profile showed 57% of samples (~1,633/2,856) in build_snapshot_payload → serde_json::to_string and a 14.6 GB physical footprint — despite the rev-gated cache supposedly preventing re-serialization on every tick

## Decision

The cache is structurally correct but rev is bumped by at least 7 different handlers (comments_handler, knowledge, feed_fetch, agent_note_handler, etc.) on essentially every actor command dispatch, invalidating the cache on every tick. The root cause is rev-churn defeating the existing cache, not missing caching; the fix must address either delta snapshots (only serialize changed podcasts/episodes), per-item cache invalidation (only re-serialize a podcast when it actually changes), or structural push changes (individual PodcastSummary updates rather than full-envelope re-serialization per tick)

## Consequences

- The fix approach shifts entirely from 'add caching' (already exists) to 'reduce rev churn or restructure the push model'
- 14.6 GB physical footprint likely caused by accumulated allocations from repeated full-library serializations every tick
- Every handler calling rev.fetch_add(1, Ordering::Relaxed) invalidates the entire library snapshot cache for the next tick

## Open Tail

- No fix was decided in this session — three candidate strategies proposed but not yet implemented
- perf_ffi_snapshot_transport.md tracks this known issue as a pre-existing reference

## Evidence

- transcript lines 30-57
- transcript lines 122-170

