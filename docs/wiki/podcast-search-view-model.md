---
title: Podcast Search View Model
slug: podcast-search-view-model
topic: ui-components
summary: "PodcastSearchViewModel uses `rerank: false` intentionally because it fires on every debounced keystroke, and the 220ms latency delta between rerank and no-reran"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-17
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:rollout-2026-05-09T14-56-23-019e0c98-8803-7ef0-b7a2-bf0b605a2360
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
  - session:rollout-2026-05-17T17-40-02-019e3661-3d9a-76d3-a4a5-f5779f6a0ee8
---

# Podcast Search View Model

## Search Rerank Setting

PodcastSearchViewModel uses `rerank: false` intentionally because it fires on every debounced keystroke, and the 220ms latency delta between rerank and no-rerank exceeds the perceptual threshold for live typing. This creates an asymmetry with HomeRelatedSheet, which uses `rerank: true`. A 4-line comment at the call site documents this rationale. Reranker settings are gated and honored by the AI/provider runtime. The query_wiki tool searches generated wiki claim bodies, ranks matches, returns excerpts/scores, and respects podcast scope. The app has a Search tab that covers shows, episodes, generated wiki pages, and transcript chunks through the live RAG stack. Discover search shows trending podcasts when the user's trimmed query is empty. When a non-empty query returns zero matches, it shows a dedicated "No results" view instead of falling back to popular/trending content. Heavy view derivations in `AllEpisodesView`, `DownloadsManagerView`, and Search must compute once per relevant state/query change inside view models, not multiple times per body render.

<!-- citations: [^rollo-49] [^0f3f2-59] [^rollo-17] [^rollo-48] [^rollo-101] [^rollo-162] -->
