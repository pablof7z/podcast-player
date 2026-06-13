---
type: episode-card
date: 2026-06-06
session: deb49f4f-f275-419a-ab1c-b68c123af73b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/deb49f4f-f275-419a-ab1c-b68c123af73b.jsonl
salience: root-cause
status: active
subjects:
  - ffi-snapshot-rebuild
  - position-for-lookup
  - build-podcast-update
supersedes: []
related_claims: []
source_lines:
  - 2057-2090
  - 2114-2148
captured_at: 2026-06-12T13:22:24Z
---

# Episode: O(N²) snapshot rebuild root cause found and fixed

## Prior State

build_podcast_update called position_for(&ep_id) for each episode, which linearly scanned every podcast's episode vector and stringified each UUID for comparison — making the full-library rebuild O(N²) with an allocation per step. At 3,600 episodes this cost ~224 ms (Mac; ~0.5–1 s on device), firing on every mark-played/star/pause and background tick.

## Trigger

Populated-library measurement (3,600 episodes) revealed 224 ms rebuilds with superlinear scaling (3.6× episodes → 10× time), and disambiguation ruled out lock contention as the cause.

## Decision

Replace s.position_for(&ep_id) with a direct read of ep.position_secs from the episode already in hand during the projection loop — a one-line, behavior-identical change that turns the rebuild from O(N²) to O(N).

## Consequences

- 224 ms → 7.6 ms at 3,600 episodes (30× speedup); now linearly scaling
- 86 snapshot tests pass unchanged — projection output is identical
- Zero wire-contract change; pure internal Rust optimization
- Measurement harness (snapshot_rebuild_perf.rs) merged as a regression guard

## Open Tail

*(none)*

## Evidence

- transcript lines 2057-2090
- transcript lines 2114-2148

