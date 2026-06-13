---
title: Episode Artwork
slug: episode-artwork
topic: data-persistence
summary: Episode does not carry an artwork field; lock-screen artwork goes through a resolver closure workaround.
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
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
  - session:rollout-2026-05-11T09-10-30-019e15a8-9491-7d33-9bbf-ee806e2f875c
---

# Episode Artwork

## Artwork

Episode does not carry an artwork field; lock-screen artwork goes through a resolver closure workaround. Artwork/card primitives must be extracted into shared `PodcastArtworkTile` and `EpisodeArtworkTile` components with configurable size, corner radius, badge, and placeholder options. Now Playing must clear cached artwork before publishing a new episode with no or new artwork to prevent leaking the previous episode's artwork.

<!-- citations: [^0f3f2-31] [^rollo-97] [^rollo-125] -->
