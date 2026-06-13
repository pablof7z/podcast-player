---
title: App Sidebar
slug: app-sidebar
topic: ui-components
summary: Tapping the top-left avatar opens a Twitter-style slide-in sidebar
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-14
updated: 2026-06-11
verified: 2026-05-14
compiled-from: conversation
sources:
  - session:1eb0c519-6723-489e-b777-71997fd7e216
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
  - session:4c830774-3f88-48e6-ab2b-ccaa1a277e00
  - session:a6320d4d-f2c8-4a8b-a21a-d71f5af73509
  - session:ec1fb244-f19d-4667-8784-28bb26786eb9
---

# App Sidebar

## Sidebar Trigger & Contents

Tapping the top-left avatar opens a Twitter-style slide-in sidebar. The sidebar displays the user's avatar (72pt, generous leading padding), display name (`title3`, semibold rounded), and `@handle` (`subheadline`), followed by navigation links: Home, Library, Bookmarks, Clippings, Wiki, and Settings. Navigation rows use a 52pt height for proper touch targets, and the active item shows a subtle accent-tinted background pill. Settings is anchored to the bottom of the sidebar above the home indicator, visually separated from the other nav items. Tapping "Podcasts" in the sidebar navigates to the podcast view by switching to the Home tab and pushing AllPodcastsListView via navigationDestination, identical to the "See all" path, instead of opening it as a sheet.

<!-- citations: [^1eb0c-1] [^e1cfd-1] [^4c830-1] [^a6320-1] [^ec1fb-6] -->
## Sidebar Animation & Layout

The sidebar uses a push-style animation: the main content slides 300pt right while the sidebar slides in from the left simultaneously. Tapping the dimmed right portion dismisses the sidebar with the same push animation. The sidebar is conditionally rendered (only in the view hierarchy when open), not always-present with an offset. <!-- [^1eb0c-2] -->

## Toolbar Changes

Search is presented as a sheet triggered by a magnifying-glass icon in the top-right toolbar. The gear icon for Settings is removed from the toolbar; Settings is accessible only from the sidebar. <!-- [^1eb0c-3] -->

## Tab Bar Behavior

The bottom tab bar is hidden via `.toolbar(.hidden, for: .tabBar)` while the mini-player continues to work via `tabViewBottomAccessory`. <!-- [^1eb0c-4] -->
