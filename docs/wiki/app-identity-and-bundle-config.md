---
title: App Identity and Bundle Config
slug: app-identity-and-bundle-config
summary: The bundle ID is io.f7z.podcast, not com.podcastr.app (which is the App Group).
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-03
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:a6320d4d-f2c8-4a8b-a21a-d71f5af73509
---

# App Identity and Bundle Config

## Bundle ID

The bundle ID is io.f7z.podcast, not com.podcastr.app (which is the App Group). <!-- [^14943-102] -->

## Source Directory

The live iOS app compiles from `App/Sources/`, not the decommissioned legacy `ios/Podcast/Podcast/` directory. [^a6320-1]

## Tab Set

The real tab set in the app is home, library, bookmarks, clippings, and wiki. [^a6320-2]
