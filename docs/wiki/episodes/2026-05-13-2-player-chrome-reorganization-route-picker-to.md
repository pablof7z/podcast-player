---
type: episode-card
date: 2026-05-13
session: 513924f8-3b98-47b0-a84a-38086416581a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/513924f8-3b98-47b0-a84a-38086416581a.jsonl
salience: product
status: active
subjects:
  - player-chrome
  - route-picker
  - playback-speed
supersedes: []
related_claims: []
source_lines:
  - 59-392
captured_at: 2026-06-12T12:12:08Z
---

# Episode: Player chrome reorganization: route picker to scrubber, speed to menu

## Prior State

AirPlay route picker and speed chip were in the top bar alongside share and more buttons; back button was a labeled capsule

## Trigger

User directive to move output device to right of progress bar and move playback speed into the … menu

## Decision

Moved RoutePickerView from PlayerTopBar to PlayerView's floatingChrome HStack next to the scrubber; moved speed control into PlayerMoreMenu as first menu item; simplified back button to a plain chevron-left circle icon matching other top bar buttons

## Consequences

- Top bar reduced to 3 uniform circle buttons (back, share, …)
- Speed adjustment now requires an extra tap via menu
- Route picker is contextually placed next to playback timeline
- All top bar buttons share same 44×44 glass circle style

## Open Tail

*(none)*

## Evidence

- transcript lines 59-392

