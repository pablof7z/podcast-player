---
type: episode-card
date: 2026-06-11
session: ec1fb244-f19d-4667-8784-28bb26786eb9
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/ec1fb244-f19d-4667-8784-28bb26786eb9.jsonl
salience: product
status: active
subjects:
  - sidebar-podcasts-nav
  - navigation-presentation-style
supersedes:
  - 2026-06-02-1-sidebar-podcasts-section-replaced-by-single
related_claims: []
source_lines:
  - 1-1
  - 21-48
  - 362-384
  - 543-565
captured_at: 2026-06-12T13:49:23Z
---

# Episode: Sidebar Podcasts navigation changed from sheet to push

## Prior State

Tapping 'Podcasts' in the sidebar opened AllPodcastsListView as a modal sheet (with a 'Done' button), disconnected from the Home NavigationStack

## Trigger

User explicitly requested: 'it shouldn't open as a sheet — it should navigate to the podcast view just like when I tap on See all'

## Decision

Replaced sheet presentation with an in-tab navigation push: sidebar callback now switches to Home tab and sets showAllPodcasts=true, which pushes AllPodcastsListView via .navigationDestination(isPresented:) inside the Home NavigationStack — identical path to 'See all'

## Consequences

- AllPodcastsListView now uses standard back-chevron navigation instead of a dismiss button
- Users can drill into ShowDetailView from the pushed list naturally
- Removed the .sheet(isPresented: $showPodcastsSheet) modifier and the showPodcastsSheet state variable entirely
- HomeView now accepts showAllPodcasts as a @Binding rather than owning it locally

## Open Tail

*(none)*

## Evidence

- transcript lines 1-1
- transcript lines 21-48
- transcript lines 362-384
- transcript lines 543-565

