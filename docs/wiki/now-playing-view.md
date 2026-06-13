---
title: Now Playing View
slug: now-playing-view
topic: ui-components
summary: The output device picker is positioned as a button to the right of the progress bar
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:513924f8-3b98-47b0-a84a-38086416581a
  - session:82bb4074-1526-4549-8697-19bfe9a117be
  - session:2a4cc6d5-8204-4e85-9d30-198832dc52a2
---

# Now Playing View

## Layout & Controls

The output device picker is positioned as a button to the right of the progress bar. Playback speed control is placed inside the "..." more menu. <!-- [^51392-5] -->

## Player Top Bar

The back button in the player top bar is a plain chevron.left icon in a 44×44 circle matching the other buttons' style.

Tapping the episode title in PlayerView presents EpisodeDetailView as a sheet on top of the player (rather than dismissing the player first). The presentation is driven by an EpisodeDetailTarget Identifiable struct wrapping a UUID via a `.sheet(item:)` modifier. PlayerView handles all `.openEpisodeDetailRequested` notifications itself via `onReceive` and presents the sheet directly, rather than delegating to RootView. (Previously: Tapping the episode title navigated to the episode detail page.)

The EpisodeDetailView sheet must explicitly inject `.environment(state)` for PlaybackState because iOS 26 does not reliably propagate nested-sheet environments, and simultaneous dismissal/presentation of sheets on the same parent view crashes on iOS 26. <!-- [^2a4cc-2] -->

PlayerNavSheets only handles show navigation and no longer contains the episode detail sheet or episodeID binding. <!-- [^2a4cc-3] -->

<!-- citations: [^51392-6] [^82bb4-1] [^2a4cc-1] -->
## Download Progress

The download indicator badge still exists in the player episode header, and a generationSourceChip is displayed below it when the episode has a generationSource. (Previously: Download progress in the player is shown as a shaded fill within the progress bar (extending from the left edge to the download position), and the download indicator badge is removed from the player episode header. <!--  -->, superseded — see episode-generation-source.)

## What's New

A whats-new entry is added per AGENTS.md for the tappable title feature. <!-- [^82bb4-2] -->
