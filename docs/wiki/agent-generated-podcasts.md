---
title: Agent-Generated Podcasts
slug: agent-generated-podcasts
summary: Agent-generated podcasts intentionally do not create a `PodcastSubscription` row, so they appear in the library's 'See All' list but not in the user's followed-
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
---

# Agent-Generated Podcasts

## Library Visibility

Agent-generated podcasts create a `Podcast` row but no `PodcastSubscription`, causing them to appear in the library's 'See All' list but not in the user's followed-podcasts list.

<!-- citations: [^e1cfd-13] [^e1cfd-16] -->
## See Also

