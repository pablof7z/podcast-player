---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-serialization
  - perf-ffi-snapshot-transport
  - build-snapshot-payload
supersedes:
  - 2026-06-12-1-snapshot-rev-cache-defeated-full-library
related_claims: []
source_lines:
  - 30-57
  - 122-160
  - 161-170
captured_at: 2026-06-12T22:05:45Z
---

# Episode: Snapshot rev-gated cache defeated by per-tick rev bumps

## Prior State

The rev-gated snapshot-string cache in `build_snapshot_payload` was believed to make repeated snapshot serialization cheap — an unchanged rev returns a cached clone, avoiding re-serialization.

## Trigger

CPU profile of process 21680 showed 57% of samples (~1633/2856) inside `serde_json::to_string` within `build_snapshot_payload`, plus a 14.6 GB physical footprint from accumulated allocations.

## Decision

The cache is structurally defeated: `rev.fetch_add(1, Ordering::Relaxed)` is called across many handlers (comments, feed_fetch, knowledge, agent_note, etc.), causing rev to bump on essentially every actor tick. Every command dispatch triggers `emit_now` → `make_update` → full-library JSON re-serialization. The leaf bottleneck (`format_escaped_str`) is just serde doing its job on a huge payload — the real fix must reduce what gets serialized per tick (delta snapshots, cached serialized form per-podcast, or structural push of individual `PodcastSummary` updates).

## Consequences

- Full-library JSON serialization on every tick is the confirmed root cause of the known perf issue in `perf_ffi_snapshot_transport.md`
- 14.6 GB physical footprint likely from accumulated allocations of repeated full-library serializations
- Fixes must target serialization volume, not serde itself
- Three candidate approaches identified: delta snapshots, per-podcast serialized-form caching, or structural push of individual updates

## Open Tail

- No specific fix adopted yet in this session — the diagnosis establishes the constraint for future implementation

## Evidence

- transcript lines 30-57
- transcript lines 122-160
- transcript lines 161-170

