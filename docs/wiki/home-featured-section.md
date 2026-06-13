---
title: Home Featured Section
slug: home-featured-section
topic: ui-components
summary: HomeFeaturedSection's onOpenThread parameter defaults to an empty no-op closure; it is silent if unwired.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Home Featured Section

## On-Open-Thread Default

HomeFeaturedSection's onOpenThread parameter defaults to an empty no-op closure; it is silent if unwired. <!-- [^0f3f2-38] -->

HomeFeaturedSection's onOpenThread parameter defaults to an empty no-op closure; it is silent if unwired. <!-- [^rollo-98] -->

## Find Related Action

"Find related" on Home featured cards must be moved into `EpisodeRowContextMenu` as an optional menu item or made a visible card action, eliminating the conflicting separate long-press gesture. <!-- [^rollo-99] -->

## Triage Shimmer

The triage shimmer in HomeFeaturedSection reads `inbox_triage_in_progress` from the PodcastUpdate projection to show a shimmer card while background LLM triage runs. <!-- [^c1691-114] -->
