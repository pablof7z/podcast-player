---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-cache
  - rev-bumping
  - performance
supersedes: []
related_claims: []
source_lines:
  - 122-161
captured_at: 2026-06-12T14:47:13Z
---

# Episode: Rev-gated snapshot cache defeated by over-bumping

## Prior State

Code comments claimed `build_snapshot_payload` had a rev-gated snapshot-string cache: 'an unchanged rev is a cheap clone, not a full serialize.' The cache logic (`handle.snapshot_cache.lock`) was correct in isolation.

## Trigger

Profiling showed 57% of CPU in `serde_json::to_string` despite the cache. Grepping `rev.fetch_add(1, Ordering::Relaxed)` revealed dozens of call sites across `comments_handler`, `feed_fetch`, `knowledge`, `agent_note_handler`, etc. — the rev bumped on essentially every actor tick, defeating the cache entirely.

## Decision

The caching approach was structurally insufficient; the real fix required reducing what gets serialized per tick (the per-domain delta architecture). The cache remains as a safety net for genuinely idle periods, but the architectural answer is per-domain sidecars.

## Consequences

- Invalidated the 'just cache the serialized form' approach as a standalone solution
- Drove the per-domain architecture: if you can't avoid re-serializing, serialize only what changed
- The rev counter's role shifted from a cache key to a domain-scoped monotonic version for the drop guard

## Open Tail

*(none)*

## Evidence

- transcript lines 122-161

