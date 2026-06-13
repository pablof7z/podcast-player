---
type: episode-card
date: 2026-06-08
session: c33b9adb-9d1a-4717-9314-b45a61e6cbc3
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c33b9adb-9d1a-4717-9314-b45a61e6cbc3.jsonl
salience: architecture
status: active
subjects:
  - android-snapshot-delivery
  - kernel-bridge
  - push-vs-poll
supersedes: []
related_claims: []
source_lines:
  - 243-251
captured_at: 2026-06-12T13:31:41Z
---

# Episode: Android snapshot polling replaced by pre-existing push channel

## Prior State

MainActivity polled kernel snapshots at ~2 Hz (500 ms interval) using a while-true loop with delay, wasting cycles and adding latency between state changes and UI updates.

## Trigger

Discovery that the reactive push path already existed end-to-end (on_update callback → mpsc channel → nativeNextUpdate → KernelBridge.nextUpdate()) but was simply unused by the UI layer.

## Decision

Replaced the 500 ms polling loop with the existing reactive push channel. Load-bearing correctness argument verified: push coverage is a strict superset of poll coverage — every bump_snapshot_rev routes through SnapshotUpdateSignal::bump() → push.

## Consequences

- Eliminates unnecessary 2 Hz polling on Android main thread
- Snapshots arrive immediately on state change rather than up to 500 ms late
- Proves existing kernel→host push infrastructure was sufficient — no new FFI needed

## Open Tail

*(none)*

## Evidence

- transcript lines 243-251

