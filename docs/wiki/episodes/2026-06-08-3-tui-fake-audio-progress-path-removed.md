---
type: episode-card
date: 2026-06-08
session: c33b9adb-9d1a-4717-9314-b45a61e6cbc3
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c33b9adb-9d1a-4717-9314-b45a61e6cbc3.jsonl
salience: root-cause
status: active
subjects:
  - tui-audio-progress
  - position-reporting
  - platform-exceptions
supersedes: []
related_claims: []
source_lines:
  - 229-239
captured_at: 2026-06-12T13:31:41Z
---

# Episode: TUI fake audio-progress path removed

## Prior State

The TUI stub fabricated playback position (last_position_secs += 0.25) when no mpv backend existed — producing a fake signal with no real data, making progress appear to advance when nothing was actually playing.

## Trigger

Finding that fabricated progress was a misleading signal; genuine platform constraints (mpv IPC, ExoPlayer within-segment sampling) need explicit documentation rather than being masked by fake data.

## Decision

Removed the TUI fake audio-progress path entirely. Framed the unavoidable position-sampling cases (mpv IPC, ExoPlayer) as explicit documented platform exceptions. Kept the main.rs sleep tick as the UI animation render clock (drives spinners, marquee, progress bars) since it cannot be made event-driven without freezing animations.

## Consequences

- No fabricated progress in TUI — removed misleading signal
- mpv IPC and ExoPlayer position sampling documented as legitimate platform exceptions rather than hidden fakes
- Animation tick clock retained but decoupled from audio position reporting

## Open Tail

- TUI samples mpv position but its polling cadence may still need scrutiny

## Evidence

- transcript lines 229-239

