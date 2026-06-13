---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-cache-defeat
  - rev-bumping
  - perf-hot-path
supersedes: []
related_claims: []
source_lines:
  - 30-57
  - 122-161
  - 163-170
captured_at: 2026-06-12T12:10:51Z
---

# Episode: Rev-gated snapshot cache defeated by excessive rev bumps

## Prior State

The `build_snapshot_payload` function was believed to have a working rev-gated cache — if `rev` hadn't changed, it would return a cheap clone of the cached JSON string, avoiding full-library re-serialization.

## Trigger

CPU sampling showed 57% of samples (~1633/2856) in `build_snapshot_payload` → `serde_json::to_string`, and 14.6 GB physical footprint. Investigation revealed `rev.fetch_add(1, Ordering::Relaxed)` called from many unrelated handlers (comments, feed_fetch, knowledge, agent_note, etc.), bumping rev on essentially every actor tick and invalidating the cache every time.

## Decision

The cache architecture is fundamentally insufficient: a single global rev bumps on too many unrelated state changes, so full-library serialization fires on every tick regardless. The fix must be per-domain revs (each domain gated independently) so a playback tick doesn't re-serialize the entire library.

## Consequences

- The single global rev is the root cause of the 10x-scale perf problem; replacing it with per-domain revs unblocks the performance fix
- Any future state addition must either use its own domain rev or accept that it will force full re-serialization of unrelated domains
- The monolithic `podcast.snapshot` pull path remains correct for cold-start hydration but must not be the hot-path delivery mechanism

## Open Tail

- Per-domain typed sidecar implementation is the planned fix (Track 1, cycle-3)

## Evidence

- transcript lines 30-57
- transcript lines 122-161
- transcript lines 163-170

