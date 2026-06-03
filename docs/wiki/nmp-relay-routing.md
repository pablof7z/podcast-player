---
title: NMP Relay Routing
slug: nmp-relay-routing
summary: All Nostr relay communication is routed through NMP's relay pool — the iOS shell never opens URLSessionWebSocketTask connections to Nostr relays
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:c43d5e77-d667-4e71-a574-47aaab5b6a7a
---

# NMP Relay Routing

## Relay Routing Architecture

All Nostr relay communication is routed through NMP's relay pool — the iOS shell never opens URLSessionWebSocketTask connections to Nostr relays. The podcast app never specifies relay URLs at publish or subscribe time — it sets app relays once at startup and lets NMP drive all routing. [^c43d5-22]


## Publish Operations

Publish operations use nmp.publish action dispatch with PublishTarget::Auto, which routes through NMP's relay pool without explicit relay URLs. Author claims (kind:10064), comments (kind:1111), and agent notes (kind:1) use PublishRaw dispatch through NMP's kernel so it signs with the active signer — no Rust secret access needed. Feedback publishing routes through the kernel like FeedbackStore instead of opening WebSocket connections to relay.tenex.chat from Swift.

<!-- citations: [^c43d5-23] [^c43d5-33] -->
## Subscribe Operations

Subscribe operations use EnsureInterest + KernelEventObserver instead of iOS capability dispatch — NMP routes subscriptions through configured relays automatically. kind:10154 show discovery uses EnsureInterest with ViewDependencies, routing through NMP's relay pool without specifying relay URLs. Comments fetching dispatches podcast.fetch_comments to the kernel (which uses push_interest + CommentsObserver) instead of calling NostrCommentService via WebSocket.

<!-- citations: [^c43d5-24] [^c43d5-34] -->
## Profile and Auth Operations

Profile fetching uses the kernel's claimProfile action (nmp_app_claim_profile) via EnsureInterest kind:0 instead of Swift WebSocket connections. NIP-46 nostrConnect pairing uses the kernel's nmp_app_signin_bunker path; Swift must never hold a RemoteSigner or manage NIP-46 WebSocket connections.

<!-- citations: [^c43d5-25] [^c43d5-35] -->
## See Also

