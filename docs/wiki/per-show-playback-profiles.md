---
title: Per-Show Playback Profiles
slug: per-show-playback-profiles
topic: playback
summary: Per-show playback profiles allow individual episodes to have their own playback settings
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-13
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
---

# Per-Show Playback Profiles

## Per-Show Playback Profiles

Per-show playback profiles allow individual episodes to have their own playback settings. A skip intro chip is an optional follow-up feature. iCloud sync is out of scope for per-show playback profiles. <!-- [^0f3f2-54] -->

## Known Issues

PlaybackState.adSegments becomes stale after detection (commit 5d). Old episodes never receive introEnd/outroStart backfill. SubscriptionRefreshService may wholesale-replace a user's saved playback profile on poll. <!-- [^0f3f2-55] -->
