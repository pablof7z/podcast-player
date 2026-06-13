---
type: episode-card
date: 2026-06-08
session: c33b9adb-9d1a-4717-9314-b45a61e6cbc3
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c33b9adb-9d1a-4717-9314-b45a61e6cbc3.jsonl
salience: root-cause
status: active
subjects:
  - android-sleep-timer
  - exo-player-capability
  - nmp-contract
supersedes: []
related_claims: []
source_lines:
  - 198-215
captured_at: 2026-06-12T13:31:41Z
---

# Episode: Android sleep timer was a silent no-op reporting success

## Prior State

ExoPlayerCapability.kt handled set_sleep_timer with a silent no-op — it accepted the command, returned success, and armed nothing. Rust's PlayerActor armed the timer and waited for the host to report SleepTimerFired, which never came from Android.

## Trigger

Bug diagnosis: the kernel contract requires the host to report timer expiry, but Android silently discarded the command while claiming success, breaking the NMP contract.

## Decision

Implemented a real wall-clock timer via Handler(Looper.getMainLooper()) + nullable Runnable, mirroring iOS AudioCapability's DispatchSourceTimer. On expiry, emits the canonical {"type":"sleep_timer_fired"} but does NOT stop the player itself — D7/D9 doctrine: the kernel decides playback stop.

## Consequences

- Sleep timer now fires correctly on Android with platform parity to iOS
- Host reports timer expiry to kernel rather than acting on it autonomously
- Establishes that capability methods must not report success for actions they do not perform

## Open Tail

*(none)*

## Evidence

- transcript lines 198-215

