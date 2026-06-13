---
type: episode-card
date: 2026-06-02
session: 4c830774-3f88-48e6-ab2b-ccaa1a277e00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4c830774-3f88-48e6-ab2b-ccaa1a277e00.jsonl
salience: root-cause
status: active
subjects:
  - sheet-navigation-stability
  - root-view
  - app-sidebar-view
supersedes: []
related_claims: []
source_lines:
  - 196-529
captured_at: 2026-06-12T12:57:03Z
---

# Episode: Sheet ownership moved from animated sidebar to stable RootView

## Prior State

Podcasts sheet state (`showPodcastsSheet`) lived inside AppSidebarView, which is an animated offset view that slides off-screen on dismiss.

## Trigger

Bug report: tapping a podcast navigates to ShowDetailView but then immediately pops back to the list. Root cause: sheets presented from offset/animated views have navigation instability — the sidebar's slide-out animation causes the pushed navigation to pop.

## Decision

Moved sheet ownership to RootView's stable tabBar view (alongside Settings, Search, and Agent Chat sheets). AppSidebarView now uses a callback (`onShowPodcasts`) instead of owning sheet state.

## Consequences

- Navigation push from the podcast sheet no longer gets ejected by the sidebar animation
- Establishes/reinforces invariant: all sheets must anchor on stable views, not on animated/offset overlays
- AppSidebarView becomes stateless regarding sheet presentation

## Open Tail

*(none)*

## Evidence

- transcript lines 196-529

