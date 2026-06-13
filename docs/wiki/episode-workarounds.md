---
title: Episode Workarounds
slug: episode-workarounds
topic: data-persistence
summary: "Episode.externalSubscriptionID and isAgentGenerated:true are named workarounds for the missing 'known but unfollowed podcast' concept."
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
  - session:84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
  - session:9833dc25-72f9-4d4f-98d9-df476ead3e6d
  - session:rollout-2026-05-10T00-02-36-019e0e8c-9c89-7dc1-9942-c63cb0efd9c4
  - session:rollout-2026-05-13T09-40-04-019e2010-60db-72b0-af0f-d40f44ca1989
  - session:rollout-2026-05-13T12-06-20-019e2096-4937-7fa1-bf10-5bb75b265a8d
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Episode Workarounds

## Workarounds

Episode.externalSubscriptionID and isAgentGenerated:true are named workarounds for the missing 'known but unfollowed podcast' concept. Agent-generated podcasts intentionally do NOT auto-subscribe the user — they create a Podcast row but no PodcastSubscription, so episodes appear in 'See All' but not in the followed-podcasts list. External episode playback must not await full feed adoption before starting; playback should begin with an existing/Unknown podcast ID and hydrate only podcast metadata asynchronously, avoiding hanging behind a slow feed request and adding the show's backlog without a subscription. The `subscribe_podcast` agent tool must check `store.subscription(podcastID:)` after resolving the podcast, not `store.podcast(feedURL:)`, so that known-but-unfollowed podcasts do not incorrectly return `already_subscribed: true` and fail to create a `PodcastSubscription`. The Discover UI subscribe checkmark must be based on `store.subscription(podcastID:)` after resolving the feed, not `store.podcast(feedURL:)`, so that known-but-unfollowed podcasts do not show a disabled checkmark that prevents subscription. OPML import must check duplicates against `state.subscriptions`, not `state.podcasts`, so that known-but-unfollowed feeds are not incorrectly skipped and receive their follow row. The All Podcasts affordance must render whenever there are non-unknown podcasts, even if the followed list is empty, so users can reach it without needing to follow at least one show. Episode.pubDate is non-optional; code must not treat it as optional. The test target must compile after the model split; fixtures using the old `Episode(subscriptionID:)` initializer must be migrated to `podcastID` or provided a compatibility initializer before landing the refactor. Episodes are persisted in a SQLite sidecar database alongside a metadata-only JSON file; on first launch, existing monolithic JSON state files are migrated to this split format. The owned-podcast private-to-public flip now self-enqueues one publish_episode action per episode via nmp_app_dispatch_action (returning immediately, D8), replacing the synchronous loop that blocked the actor.

<!-- citations: [^0f3f2-36] [^84c4d-11] [^e1cfd-9] [^9833d-7] [^rollo-26] [^rollo-137] [^rollo-141] [^c1691-100] -->
