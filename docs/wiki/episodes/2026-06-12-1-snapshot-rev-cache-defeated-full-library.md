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
  - 2026-06-12-1-snapshot-serialization-rev-churn-defeats-rev
  - 2026-06-12-3-rev-gated-snapshot-cache-defeated-by
related_claims: []
source_lines:
  - 30-57
  - 134-161
captured_at: 2026-06-12T21:53:41Z
---

# Episode: Snapshot rev-cache defeated — full-library re-serialization on every tick

## Prior State

build_snapshot_payload had a rev-gated snapshot-string cache (line 291–306 of snapshot.rs); on an unchanged revision it returns a cheap clone, avoiding re-serialization

## Trigger

CPU profile of process 21680 showed 57% of samples (1,633/2,856) in serde_json::to_string inside build_snapshot_payload, plus a 14.6 GB physical footprint. Investigation revealed the rev counter is bumped by multiple handlers (comments, feed_fetch, knowledge, agent_note, etc.) on essentially every actor tick, defeating the cache

## Decision

The cache is structurally defeated — rev bumps too frequently for it to help. The real fix must be one of: (1) delta snapshots (serialize only changed podcasts/episodes), (2) per-podcast cached serialized forms, or (3) structural change (push individual PodcastSummary updates rather than full PodcastUpdate envelope per tick). Leaf bottleneck (format_escaped_str) is serde doing its job on a huge payload — reducing payload size is the only durable fix.

## Consequences

- Every command dispatch triggers emit_now → full-library JSON re-serialization on the actor thread (D8 violation of 'must be cheap, non-blocking')
- 14.6 GB physical footprint from accumulated allocations of repeated full-library serializations
- The three fix paths are documented in the codebase's perf_ffi_snapshot_transport.md

## Open Tail

- No fix was implemented in this session — the diagnosis changes future implementation but the remedy is pending

## Evidence

- transcript lines 30-57
- transcript lines 134-161

