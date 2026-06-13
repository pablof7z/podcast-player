---
title: Nostr Episode Hydration
slug: nostr-episode-hydration
topic: nostr-protocol
summary: "Nostr kind:54 episode fetch uses a lazy reactive observer (NostrEpisodesObserver registered before relay interest opens), so feedless Nostr-native podcasts hydr"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-12
updated: 2026-06-13
verified: 2026-06-12
compiled-from: conversation
sources:
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Nostr Episode Hydration

## Episode Hydration

Nostr kind:54 episode fetch uses a lazy reactive observer (NostrEpisodesObserver registered before relay interest opens), so feedless Nostr-native podcasts hydrate episodes via kind:54 events, completing the NIP-F4 publish→discover→listen loop. Nostr feedless podcast subscription uses a deterministic UUIDv5 namespace ("nostr:show:{pubkey}") for PodcastId, ensuring collision-free store rows that are skipped by all_feed_infos/refresh and hydrated exclusively via kind:54 events through the reactive observer. The OnceLock observer registration in nostr_episodes.rs has a theoretical edge where a null app no-ops but still seals the OnceLock, preventing later valid-app registration; production never hits this (app is non-null for the process lifetime) but a guard would harden it. The owned-podcast private→public visibility flip backfills per-episode kind:54 events via per-episode self-enqueue (nmp_app_dispatch_action), not a synchronous loop, to avoid blocking the actor. NIP-10 Nostr conversations are owned by the kernel via the podcast.social domain sidecar, grouping inbound AgentNoteSummary and OutboundTurn entries by root_event_id, merging turns in timestamp order, and computing trusted live against the follow set. The kind:0 profile hydration decision for conversations is to ride the existing resolved_profiles seam (claimProfile on view-appear), not duplicate kind:0 into podcast.social. iOS SocialDomainFrame uses no explicit CodingKeys (convertFromSnakeCase contract), and the nostrConversationFromDTO mapper converts wire rootEventId to domain rootEventID (uppercase) and string direction to Direction enum.

<!-- citations: [^c1691-211] [^c1691-77] [^c1691-78] [^c1691-46] [^c1691-76] [^c1691-90] [^c1691-107] [^c1691-121] [^c1691-161] [^c1691-183] [^c1691-196] [^c1691-210] [^c1691-225] [^c1691-244] -->
