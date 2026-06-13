---
type: episode-card
date: 2026-06-04
session: e1ab0629-64bc-4383-bd22-c0843ca16a99
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/e1ab0629-64bc-4383-bd22-c0843ca16a99.jsonl
salience: architecture
status: superseded
subjects:
  - audio-report-rev-discipline
  - snapshot-rebuild-hotpath
  - now-playing-inline-path
supersedes: []
related_claims: []
source_lines:
  - 152-165
  - 5943-5970
  - 6097-6105
  - 6131-6148
captured_at: 2026-06-12T13:15:22Z
---

# Episode: Playback position ticks no longer rebuild full library snapshot

## Prior State

Every 1 Hz Playing/BufferingProgress tick unconditionally bumped the global podcast rev, triggering a full Rust serialize + Swift main-thread JSON decode of the ~3,600-episode library on each tick. Phone thermally pegged during playback.

## Trigger

User reported phone overheating during playback; profiling traced the hotpath to per-tick snapshot rebuilds driven by audio position bumps.

## Decision

Audio report now returns {follow_up, now_playing, durable_changed}. Playing/BufferingProgress ticks ride an inline PlayerState payload and do NOT bump rev. Only structural state changes (play/pause/stop/track-end) set durable_changed=true and take the full snapshot path.

## Consequences

- Scrubber, Dynamic Island, and lock screen stay live via the already-decoded library snapshot + inline now_playing payload
- Full-library re-serialize/decode only fires on genuine structural events, not every position tick
- The Rust FFI boundary changed: nmp_app_podcast_audio_report now returns AudioReportResponse with three fields instead of a single boolean
- Swift side requires reconcileLiveActivity and now-playing extraction from the inline payload, not from the full snapshot

## Open Tail

- If scrubber or lock-screen freezes during playback, the inline reconcile path is the likely regression point
- On-device validation was not automated (xctrace tunnel and UI harness both blocked); manual 20-second playback test needed

## Evidence

- transcript lines 152-165
- transcript lines 5943-5970
- transcript lines 6097-6105
- transcript lines 6131-6148

