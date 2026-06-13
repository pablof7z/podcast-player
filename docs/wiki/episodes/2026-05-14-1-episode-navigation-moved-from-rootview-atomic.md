---
type: episode-card
date: 2026-05-14
session: 2a4cc6d5-8204-4e85-9d30-198832dc52a2
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/2a4cc6d5-8204-4e85-9d30-198832dc52a2.jsonl
salience: architecture
status: active
subjects:
  - player-episode-navigation
  - sheet-presentation-lifecycle
  - ios26-compat
supersedes: []
related_claims: []
source_lines:
  - 791-806
captured_at: 2026-06-12T12:25:01Z
---

# Episode: Episode navigation moved from RootView atomic-flip to PlayerView stacked sheet

## Prior State

Tapping the episode title in PlayerView posted a notification to RootView, which performed an 'atomic flip' — dismissing the player sheet and presenting EpisodeDetailView in the same render tick via PlayerNavSheets.

## Trigger

iOS 26 crashes when two sheets on the same parent view change state (dismiss + present) in the same render pass. Crash reproduced in simulator.

## Decision

Episode navigation moved entirely inside PlayerView: PlayerView catches .openEpisodeDetailRequested notifications itself and presents EpisodeDetailView as a sheet ON TOP of the player (player stays open). RootView's clipSourceEpisodeID binding and the episode sheet in PlayerNavSheets were removed. PlayerNavSheets now only handles show navigation.

## Consequences

- UX change: episode detail slides up over the player; user dismisses to return to player (instead of player dismissing first)
- RootView simplified — no longer manages episode sheet state
- Eliminates the two-sheet race condition on iOS 26
- Any future sheet-within-sheet navigation must explicitly inject @Environment values that originate above the first sheet

## Open Tail

*(none)*

## Evidence

- transcript lines 791-806

