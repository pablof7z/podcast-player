---
title: Nostr Discovery and Relay Routing
slug: nostr-discovery-and-relay-routing
summary: "The `discover_nostr` `NostrDiscoveryObserver` deduplicates arriving kind:10154 events by author pubkey"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-01
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Nostr Discovery and Relay Routing

## Nostr Discovery and Relay Routing

NMP core owns ALL relay connections — iOS must never open a URLSessionWebSocketTask to a Nostr relay. The podcast app registers interests/subscriptions with NMP and receives events through the push frame. NostrRelayCapability.swift must be deleted for discovery paths and replaced with NMP's EnsureInterest/LogicalInterest pattern; NMP routes through the user's configured app relays and NIP-65 outbox read relays automatically with no relay URL specified by the app. Podcast show discovery uses InterestScope::Global and is_indexer_discovery: true with no relay_pin, allowing NMP to route through app relays and the user's NIP-65 outbox read relays automatically. NostrRelayCapability.swift is retained only for outbound publish paths (kind:1 agent notes, kind:54/10154 NIP-F4 publish, kind:1111 comments) which still require dispatch_capability.

<!-- citations: [^14943-120] [^14943-151] -->
## Relay Configuration UI

The relay config UI allows configuring app relays with roles including indexer and content, plus user NIP-65 relays and agent NIP-65 relays. <!-- [^14943-121] -->

## Relay Configuration Persistence

Relay configuration persists across app restarts via disk-based save/load in relay_config.rs.

<!-- citations: [^14943-122] [^14943-152] -->
