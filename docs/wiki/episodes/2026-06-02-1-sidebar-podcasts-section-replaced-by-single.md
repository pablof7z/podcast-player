---
type: episode-card
date: 2026-06-02
session: 4c830774-3f88-48e6-ab2b-ccaa1a277e00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4c830774-3f88-48e6-ab2b-ccaa1a277e00.jsonl
salience: product
status: superseded
subjects:
  - sidebar-podcasts
  - app-sidebar-view
supersedes: []
related_claims: []
source_lines:
  - 78-194
captured_at: 2026-06-12T12:57:03Z
---

# Episode: Sidebar podcasts section replaced by single nav row

## Prior State

Sidebar contained AppSidebarPodcastsSection rendering up to 5 podcast rows inline with a "See All (N)" affordance, making the sidebar a browse surface for podcasts rather than a navigation shortcut.

## Trigger

User correction: the sidebar was supposed to just be a link to navigate to the podcast view, not show all podcasts on the sidebar.

## Decision

Collapsed the entire inline section into a single "Podcasts" nav row that dismisses the sidebar and opens AllPodcastsListView in a sheet. Deleted AppSidebarPodcastsSection.swift entirely.

## Consequences

- Sidebar is now purely a navigation shortcut surface, not a content-browsing surface
- AppSidebarPodcastsSection.swift removed (219 lines deleted)
- Sheet for full podcast list is presented from AppSidebarView initially (later moved — see next arc)

## Open Tail

*(none)*

## Evidence

- transcript lines 78-194

