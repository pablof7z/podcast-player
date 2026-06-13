---
type: episode-card
date: 2026-06-03
session: 55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1.jsonl
salience: root-cause
status: active
subjects:
  - lock-screen
  - remote-command
  - kernel-load
  - player-state
supersedes: []
related_claims: []
source_lines:
  - 1180-1209
captured_at: 2026-06-12T13:11:23Z
---

# Episode: Lock-screen Play bypassed kernel after cold restart

## Prior State

After a cold restart, RootView+Setup restored the last-played episode into the audio engine (paused) but never sent a kernelLoad to Rust. Lock-screen Play taps ran through AudioCapability which called engine.play() directly — audio started but Rust had no episode_id for position reports.

## Trigger

Explicit task to fix the cold-restart lock-screen Play bug. Tracing revealed two competing MPRemoteCommandCenter registrants: NowPlayingCenter (correct, calls kernelLoad) and AudioCapability (the bypass path).

## Decision

Added a guarded kernelLoad in the commandHandler .play case: if Rust's nowPlaying.episodeId is nil/empty and a restored episode exists, dispatch kernelLoad first, then play. Loop-safe because Rust's Load echo lands on the .load case which never re-issues play or load.

## Consequences

- Lock-screen Play after cold restart now correctly stages the episode in Rust before starting audio
- Position persistence and mark-played both work from lock-screen after relaunch
- AudioCapability's direct engine.play() path is retained for the already-loaded case (no regression)

## Open Tail

- Physical-device validation recommended — the cold-restart-then-remote-command flow is hard to inject in the simulator

## Evidence

- transcript lines 1180-1209

