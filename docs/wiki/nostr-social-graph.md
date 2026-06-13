---
title: Nostr Social Graph
slug: nostr-social-graph
topic: nostr-protocol
summary: The social graph uses a reactive FollowListProjection riding the standing account_profile_interest subscription instead of a one-shot 8s-timeout relay pull â
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

# Nostr Social Graph

## Social Graph Adoption

The social graph uses a reactive FollowListProjection riding the standing account_profile_interest subscription instead of a one-shot 8s-timeout relay pull — no separate subscription, no polling, no relay fetch, so FetchContacts is now just a refresh trigger returning refreshed/pending.

Trust is computed live at projection time from ActiveFollowSet, not frozen at receipt; following an author immediately flips all their existing notes to trusted. Block is an absolute override — a followed-then-blocked pubkey returns untrusted.

On account switch, the identity-change hook clears both social_slot (set to None) and agent_notes (Vec cleared) so no cross-account state leaks from A into B's session. Approved peers persist per data-dir (per-account) and are NOT cleared on account switch (unlike session-scoped social state); they reload from the new account's data dir on switch.

Nostr conversations are a kernel-owned podcast.social domain projection grouping inbound AgentNoteSummary and OutboundTurn entries by root_event_id, with trusted computed live at projection time and outbound turns captured at publish time via handle_publish_agent_note. The social domain has a real production writer (infra.bump) at both mutation sites.

Approve/block actions dispatch through podcast.social and call infra.bump() at the real mutation site, re-emitting the social domain with the trust verdict flipped; a test driving the real handler confirmed this with a mutation-guard proof.

The ApprovedPeerStore provides a kernel-owned allow+block list persisted per data-dir; the trust predicate composes (followed OR approved) AND NOT blocked, and the responder and projection both consume the same composed predicate.

The ApprovedPeerStore mutex fails closed: if poisoned, the trust predicate returns false for every pubkey (deny-all), and the responder gate also denies auto-reply.

Android decodes the podcast.social domain frame into NostrConversationDto but renders nothing — zero social/conversations/friends Composables exist; iOS has the complete slice.

The social-publish-relay-target item is genuinely open: kernel social publishing still hardcodes relay.primal.net rather than targeting the user's configured write relays.

<!-- citations: [^c1691-167] [^c1691-168] [^c1691-169] [^c1691-186] [^c1691-198] [^c1691-213] [^c1691-226] [^c1691-234] [^c1691-246] [^c1691-257] [^c1691-270] -->
