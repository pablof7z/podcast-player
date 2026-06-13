---
title: Agent Picks Service
slug: agent-picks-service
topic: agent-system
summary: The 'rarely-opened shows' heuristic uses a recency proxy because real open counts are not tracked
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
  - session:rollout-2026-05-13T16-51-04-019e219a-f6d8-78d2-8c63-e09938281252
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Agent Picks Service

## Agent Picks Service

The 'rarely-opened shows' heuristic uses a recency proxy because real open counts are not tracked. The old AgentPicksService heuristic fallback path (where spokenRationale was empty) is now dead code, with the Fallback and related files remaining only because test references haven't been cleaned up. (Previously: The HomeAgentPicks spokenRationale is empty for the heuristic fallback path. <!--  -->, superseded — see inbox-triage.)

A list_podcasts tool exposes every known Podcast row with a subscribed: bool flag, filtering out the Podcast.unknownID sentinel. Tool descriptions for search_episodes, refresh_feed, subscribe_podcast, and list_subscriptions are audited to correctly reflect subscribed vs. library scope. <!-- [^f11c4-1] -->

The LLM emits an is_hero flag on at most one decision per pass (enforced by the parser); the hero is persisted as Episode.triageIsHero and the bundle builder prefers the agent's hero choice over pubDate. (Previously: The agent should emit a hero/priority signal so that hero ranking reflects editorial relevance rather than simply newest pubDate. <!--  -->, superseded — see inbox-triage.)

Android AI picks rail uses podcast.picks refresh op and renders a horizontal LazyRow of AgentPickSummary cards; picks are in the podcast.misc domain frame. <!-- [^c1691-262] -->
