---
title: Subscription Service
slug: subscription-service
topic: data-persistence
summary: The placeholder-persist bug is already fixed (commit 9f9958f)
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
  - session:f11c47b8-a7bd-47d3-9eb0-79dd02904d04
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
  - session:rollout-2026-05-11T08-21-02-019e157b-4b15-77a0-8003-a3ae75cf8c26
  - session:rollout-2026-05-11T09-10-30-019e15a8-9588-70a1-99b0-f20d08ac91a4
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Subscription Service

## Feed-Fetch Error Handling

On a feed-fetch error, the optimistic row is kept with no episodes until pull-to-refresh; surfacing that error is a tracked follow-up. (Previously: The placeholder-persist bug is already fixed (commit 9f9958f). addSubscription throws on FeedFetchError and ensurePodcast throws immediately on error, with no upsertPodcast on error paths, superseded — see podcast-subscription-flow.) The download_and_transcribe external path uses ensurePodcast (not subscribe) so it captures the Podcast row without flipping the subscribed bit. No caller (including AppIntents, Siri, Shortcuts, and CarPlay) reads library/podcastSnapshot/episodes synchronously after dispatch—all 122 dispatch sites are fire-and-forget relying on @Observable reactivity. (Previously: SubscriptionService.ensurePodcast (capture a feed without subscribing) still uses the upsertPodcast/upsertEpisodes Swift seams because it reads episodes back synchronously — a fire-and-forget kernel dispatch cannot satisfy that, superseded — see kernel-projections.) Migrating it to the kernel is a separate follow-up. Cold launch must trigger an immediate subscription refresh sweep on launch/foreground instead of waiting for the 30-minute interval loop. Legacy per-show refresh must route through SubscriptionRefreshService so that per-show and all-feed refresh share update, notification, and error behavior.

Relay configuration persistence is already shipped (commit 0dcf9680, load via ffi/data_dir.rs:112 and save via ffi/relay_persist.rs); the BACKLOG entry and a stale comment block in register.rs:233-262 claiming no persistence exists are both corrected. <!-- [^c1691-235] -->

<!-- citations: [^rollo-94] [^0f3f2-69] [^f11c4-5] [^55bed-16] [^rollo-115] -->
## Unsubscribe vs. Delete Semantics

Unsubscribing and deleting a podcast are conceptually distinct actions, though the current implementation performs a full nuke (removing Podcast, PodcastSubscription, and episodes) for both. A delete_podcast tool performs this full nuke and rejects the Unknown sentinel. Separating unsubscribe (removing PodcastSubscription but keeping Podcast + episodes) from delete (full nuke) is deferred out of scope. <!-- [^f11c4-6] -->
