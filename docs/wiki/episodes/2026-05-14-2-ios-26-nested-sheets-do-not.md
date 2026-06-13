---
type: episode-card
date: 2026-05-14
session: 2a4cc6d5-8204-4e85-9d30-198832dc52a2
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/2a4cc6d5-8204-4e85-9d30-198832dc52a2.jsonl
salience: root-cause
status: active
subjects:
  - swiftui-environment-propagation
  - ios26-compat
  - nested-sheet-pattern
supersedes: []
related_claims: []
source_lines:
  - 1194-1199
  - 1547-1565
captured_at: 2026-06-12T12:25:01Z
---

# Episode: iOS 26 nested sheets do not propagate @Environment — requires explicit injection

## Prior State

PlaybackState was injected once via .environment(playbackState) on the tabBar in RootView, and assumed to propagate through all child sheets including sheets presented from within other sheets.

## Trigger

After moving episode navigation inside PlayerView, the app still crashed with: 'Fatal error: No Observable object of type PlaybackState found. A View.environmentObject(_:) for PlaybackState may be missing as an ancestor of this view.'

## Decision

Explicitly inject .environment(state) on the NavigationStack inside the episode detail sheet in PlayerView, so EpisodeDetailView always has PlaybackState available regardless of iOS version's environment propagation behavior.

## Consequences

- Any future sheet presented from within PlayerView (or any sheet-within-sheet) must explicitly inject required @Environment objects rather than assuming propagation
- This is an iOS 26 platform behavior, not a code bug — serves as a durable pattern for all nested sheet presentations

## Open Tail

- Audit other sheet presentations within sheets (e.g. PlayerMoreMenu actions) for missing environment injection

## Evidence

- transcript lines 1194-1199
- transcript lines 1547-1565

