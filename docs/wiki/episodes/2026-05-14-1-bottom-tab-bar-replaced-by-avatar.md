---
type: episode-card
date: 2026-05-14
session: 1eb0c519-6723-489e-b777-71997fd7e216
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1eb0c519-6723-489e-b777-71997fd7e216.jsonl
salience: product
status: active
subjects:
  - navigation-model
  - root-tab
  - sidebar
  - search-sheet
supersedes: []
related_claims: []
source_lines:
  - 1214-1280
captured_at: 2026-06-12T12:23:41Z
---

# Episode: Bottom tab bar replaced by avatar sidebar navigation

## Prior State

App used a bottom TabView with four tabs (Home, Search, Clippings, Wiki) plus a gear icon for Settings in the top toolbar. Search was a dedicated tab.

## Trigger

User directive: show user avatar top-left that opens a Twitter-style sidebar with Clippings, Wiki, Settings links; move search to top-right; remove bottom tab bar entirely.

## Decision

Removed bottom tab bar visibility via `.toolbar(.hidden, for: .tabBar)` (kept TabView structurally for mini-player). Added avatar button (topBarLeading) that opens `AppSidebarView`. Moved Search to a sheet triggered by magnifyingglass icon (topBarTrailing). Reduced `RootTab` enum from 4 cases to 3 (`.search` removed).

## Consequences

- Primary navigation is now avatar-triggered sidebar instead of tab bar
- Search is a modal sheet, not a persistent tab
- TabView retained structurally only for `tabViewBottomAccessory` (mini-player)
- New files: AppSidebarView.swift, PlayerNavSheets.swift, RootView+DeepLink.swift, RootView+Setup.swift
- All `@State`/`@Environment` properties in RootView changed from `private` to `internal` for cross-file extension access

## Open Tail

*(none)*

## Evidence

- transcript lines 1214-1280

