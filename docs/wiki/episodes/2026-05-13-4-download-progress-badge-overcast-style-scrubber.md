---
type: episode-card
date: 2026-05-13
session: 513924f8-3b98-47b0-a84a-38086416581a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/513924f8-3b98-47b0-a84a-38086416581a.jsonl
salience: product
status: active
subjects:
  - download-indicator
  - player-scrubber
  - player-timeline
supersedes: []
related_claims: []
source_lines:
  - 540-733
captured_at: 2026-06-12T12:12:08Z
---

# Episode: Download progress: badge → Overcast-style scrubber shade

## Prior State

Download progress shown as a separate DownloadProgressBadge in the player episode header (with state-dependent glyphs: queued, percentage, downloaded, failed)

## Trigger

User directive: the badge is too much; use a shade in the progress bar like Overcast

## Decision

Removed DownloadProgressBadge from episode header; added downloadFraction parameter to PlayerTimelineView and drew a mid-opacity shade from left edge to download position; threaded downloadFraction through PlayerScrubberView and PlayerView

## Consequences

- Download progress is now ambient/contextual within the scrubber rather than a separate badge
- Less vertical space consumed in the header
- Visual language mirrors Overcast's familiar pattern

## Open Tail

*(none)*

## Evidence

- transcript lines 540-733

