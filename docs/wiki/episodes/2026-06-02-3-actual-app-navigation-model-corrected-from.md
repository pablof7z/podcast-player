---
type: episode-card
date: 2026-06-02
session: a6320d4d-f2c8-4a8b-a21a-d71f5af73509
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a6320d4d-f2c8-4a8b-a21a-d71f5af73509.jsonl
salience: product
status: active
subjects:
  - tab-structure
  - navigation-model
  - app-structure
supersedes: []
related_claims: []
source_lines:
  - 598-604
  - 659-663
captured_at: 2026-06-12T12:58:50Z
---

# Episode: Actual app navigation model corrected from assumed structure

## Prior State

Assumed tab bar was Home/Library/Downloads/Briefings/Social/Inbox/Agent/Identity (based on the RootTab enum in ios/Podcast/Podcast/App/RootShell.swift).

## Trigger

Maestro flows agent and a11y agent independently examined the live App/Sources/App/RootView.swift and found the actual tabs are Home/Library/Bookmarks/Clippings/Wiki. Downloads is under Settings; subscribe requires sidebar → Add Show → Discover; queue is accessed via player's PlayerQueueSheet with long-press context menu.

## Decision

All Maestro flows and a11y identifiers use the real navigation model: Home/Library/Bookmarks/Clippings/Wiki tabs, sidebar-based subscribe flow, and mini-player for playback.

## Consequences

- Maestro P0 flows use correct navigation paths (sidebar → Add Show → Discover for subscribe; tabViewBottomAccessory mini-player for playback)
- a11y identifiers follow bare-base-ID convention matching existing Maestro config (no -{id} suffixes)
- Future UI test authoring must reference the App/Sources/ RootView, not the legacy RootShell

## Open Tail

*(none)*

## Evidence

- transcript lines 598-604
- transcript lines 659-663

