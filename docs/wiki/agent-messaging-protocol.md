---
title: Agent Messaging Protocol
slug: agent-messaging-protocol
summary: "Agent-to-agent and friend/friend-agent messaging uses public kind:1 notes threaded via NIP-10; NIP-17 is an explicit non-goal"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-30
updated: 2026-06-01
verified: 2026-05-30
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Agent Messaging Protocol

## Protocol Selection

Agent-to-agent and friend/friend-agent messaging uses public kind:1 notes threaded via NIP-10, not NIP-17 (kind 14/1059), with no hedging or 'transport TBD' language. Agent-to-agent notes use kind:1 NIP-10 transport with tags [e, root, '', 'root'] + [p, peer], subscribing via {kinds:[1], #p:[me]}, self-filtering own notes, and newest-first sort. NIP-F4 is the canonical production protocol (not a legacy correction from NIP-74); no legacy data migration is needed.

<!-- citations: [^14943-96] [^14943-131] -->
