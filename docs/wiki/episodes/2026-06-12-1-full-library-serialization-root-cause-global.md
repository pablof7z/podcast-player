---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-cache-defeat
  - global-rev-bumping
  - per-domain-projections
supersedes:
  - 2026-06-12-1-full-library-re-serialization-on-every
related_claims: []
source_lines:
  - 1-57
  - 122-161
captured_at: 2026-06-12T14:21:59Z
---

# Episode: Full-library serialization root cause: global rev defeats snapshot cache

## Prior State

The rev-gated snapshot-string cache in `build_snapshot_payload` was believed to provide a fast path — skip re-serialization when `rev` hasn't changed. In practice, `rev.fetch_add(1, Ordering::Relaxed)` was called from many handlers (comments, feed_fetch, knowledge, agent_note, etc.), bumping the global rev on essentially every actor tick, defeating the cache entirely. Every command dispatch triggered `emit_now` → full library JSON serialization (~3.9 MB / ~35 ms per tick).

## Trigger

Profiling process 21680 showed 57% of CPU samples (~1,633 of 2,856) in `build_snapshot_payload` → `serde_json::to_string`, with a 14.6 GB physical footprint from accumulated allocations. Code inspection confirmed the cache exists but `rev` bumps on every tick, making it a near-complete miss.

## Decision

Replace the global-rev + full-snapshot architecture with per-domain typed sidecars (library, playback, downloads, settings, identity, widget, misc), each with its own domain-scoped rev. Unchanged domains skip serialization entirely. Playback tick now applies ~1KB delta instead of ~3.9MB full-library pull. Shells consume per-domain frames via composite merge.

## Consequences

- ~10x reduction in per-tick serialization cost for typical interactions (playback, mark-played)
- Each shell must implement per-domain frame decoding, composite merge, and per-domain rev-monotonic drop guards
- Requires tombstone contract for domains that go empty (otherwise shells can't learn 'signed out' / 'downloads cleared')
- Cold-start pull retained as fallback/hydration path; push path is the reactive channel

## Open Tail

- Each domain builder still calls full `build_podcast_update` per changed domain per tick (up to 7 full builds/tick) — acceptable post-per-domain (~7.6ms) but flagged for future optimization
- 304-NotModified library-rev bump cost becomes a pushed full library sidecar once shells consume domains

## Evidence

- transcript lines 1-57
- transcript lines 122-161

