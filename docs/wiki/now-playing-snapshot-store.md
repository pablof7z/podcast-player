---
title: Now Playing Snapshot Store
slug: now-playing-snapshot-store
topic: playback
summary: NowPlayingSnapshot no longer carries an `updatedAt` field
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-13
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:c33b9adb-9d1a-4717-9314-b45a61e6cbc3
  - session:38f8143c-c90d-49e3-a8fa-8d5ca17ac319
  - session:rollout-2026-05-11T08-21-01-019e157b-4863-7563-a43b-8405491d88a1
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Now Playing Snapshot Store

## Schema

WidgetSnapshot (kernel-built) includes 9 required fields: now_playing_episode_title, now_playing_podcast_title, now_playing_artwork_url, now_playing_chapter_title, is_playing, position_fraction, position_secs, duration_secs, unplayed_count. The nowPlayingArtworkURL property is spelled nowPlayingArtworkUrl to match the .convertFromSnakeCase acronym convention. NowPlayingSnapshot no longer carries an `updatedAt` field. The property has been removed from both the app-side and widget-side structs. Synthesized `Codable` ignores extra keys, so any old on-disk snapshots that still contain `updatedAt` will decode cleanly without error. Explicit CodingKeys were removed from WidgetSnapshot; instead, bridge decoding is centralized in KernelDecoding.swift, which all 5 decode sites route through. (Previously: PR #371 identified a decode regression where explicit snake_case CodingKeys conflicted with .convertFromSnakeCase, causing keyNotFound on is_playing.)

SettingsSnapshot uses decodeIfPresent for every field with defaults, so it physically cannot throw keyNotFound. <!-- [^c1691-271] -->

<!-- citations: [^0f3f2-53] [^38f81-9] -->
## iOS Write Path

The iOS app writes the WidgetSnapshot JSON with snake_case keys to App Group UserDefaults under the key 'nmp.widget.snapshot.v1' in the 'group.com.podcastr.app' suite, and calls WidgetCenter.reloadAllTimelines() on each write. The old Swift-based NowPlayingSnapshotStore and its 'now-playing-snapshot.v1' key were completely removed in PR #366, eliminating the parallel derivation path. The #371 decode fix is validated live: 0 decode failures, library hydrates 2,884 episodes, App Group key written with correct snake_case schema, and change-gating is active. <!-- [^38f81-10] -->

## Widget Read Path

The widget extension reads WidgetSnapshot from the same App Group UserDefaults using matching snake_case CodingKeys, and gracefully falls back to an empty state when the key is absent or malformed. During confirmed live playback, the kernel emits an idle WidgetSnapshot (is_playing=false, no now_playing_episode_title, position_fraction=0, duration_secs=0) while the iOS audio engine plays independently, meaning the #366 now-playing widget projection does not populate playing state. (Previously: After PR #373 merges, a live re-verification should confirm the App Group key nmp.widget.snapshot.v1 contains is_playing:true, a populated now_playing_episode_title, position_fraction in [0,1], and duration_secs > 0 during playback, then is_playing:false on pause. <!--  -->, superseded — see kernel-projections.)

## Playback Metadata Resolution

A PlaybackMetadataResolver should be introduced that returns one live NowPlayingMetadata for the full player, mini player, widget, and lock screen. <!-- [^rollo-77] -->

## Artwork Cache Integrity

The artwork cache must be resolved or reset before publishing Now Playing, or publishing must happen through a value object keyed by artworkURL so stale images cannot be attached to a new metadata snapshot. <!-- [^rollo-78] -->
