---
type: episode-card
date: 2026-05-15
session: a6b98d9b-32b6-49e0-9bda-3204ca8808bb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a6b98d9b-32b6-49e0-9bda-3204ca8808bb.jsonl
salience: product
status: active
subjects:
  - mini-player
  - dismiss-button
  - continue-listening
supersedes: []
related_claims: []
source_lines:
  - 619-669
captured_at: 2026-06-12T12:31:54Z
---

# Episode: MiniPlayer dismiss button removes episode from Continue Listening

## Prior State

MiniPlayer had no dismiss mechanism; users could navigate away but couldn't remove a playing episode from the mini player or from the Continue Listening list

## Trigger

User requested an × dismiss button on the mini player that removes the episode from Continue Listening, equivalent to swiping in the list

## Decision

Added an × dismiss button to MiniPlayer transport controls that pauses playback, clears the episode (state.episode = nil), and calls store.markEpisodePlayed(episodeID) to remove from Continue Listening — the same path as swipe-to-remove

## Consequences

- MiniPlayer now has a visible, accessible dismiss action
- Episode removal uses the same markEpisodePlayed path as swipe-to-remove, ensuring consistent behavior
- Haptic feedback (Haptics.warning()) fires on dismiss

## Open Tail

*(none)*

## Evidence

- transcript lines 619-669

