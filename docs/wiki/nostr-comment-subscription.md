---
title: Nostr Comment Subscription
slug: nostr-comment-subscription
topic: nostr-protocol
summary: Comment subscribe filters use lowercase #i (parent scope) and publish writes both uppercase I/K for root scope and lowercase i/k for parent scope, both pointing
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-15
updated: 2026-06-12
verified: 2026-05-15
compiled-from: conversation
sources:
  - session:f3b466c6-7791-44b3-b004-aae2066a9019
---

# Nostr Comment Subscription

## Comment Subscription Filters

Comment subscribe filters use lowercase #i (parent scope) and publish writes both uppercase I/K for root scope and lowercase i/k for parent scope, both pointing at the same identifier on top-level comments. <!-- [^f3b46-7] -->

Subscribing to Nostr events uses EnsureInterest / push_interest with ViewDependencies; NMP routes through configured relays automatically, no URL specification needed. (Previously: Thread subscriptions use two SubscriptionIds sharing one Arc<ThreadRouter> because nostr-sdk 0.44.1's subscribe_with_id accepts only a single Filter. <!--  -->, superseded — see nostr-rust-ffi.)

Thread reply filters pin kind:1 to prevent kind:7 reactions and kind:9735 zaps from polluting the conversation view. <!-- [^f3b46-9] -->

CommentAnchor wire format for episodes is podcast:item:guid:<guid> with kind podcast:item:guid, and for clips is podcastr:clip:<uuid> (uuid lowercased) with kind podcastr:clip. <!-- [^f3b46-10] -->

## Cancellation and EOSE Handling

Subscribing to Nostr events uses EnsureInterest / push_interest with ViewDependencies; NMP routes through configured relays automatically, no URL specification needed. (Previously: NostrCommentService.subscribe uses a per-callbackID Session with an optional relaySubID and a cancelled latch to handle cancellation that fires before the relay subscription id arrives. <!--  -->, superseded — see nostr-rust-ffi.)

All ad-hoc Nostr code is moved to the Rust side, exclusively event-driven with no polling, using the nostr-sdk in Rust. (Previously: NostrThreadFetcher uses a WaitState that latches eose/timeout flags independently of the continuation to handle EOSE firing before withCheckedContinuation installs the continuation. <!--  -->, superseded — see nostr-rust-ffi.)

## PeerMessageRecord Storage

No WebSocket awareness (URLSessionWebSocketTask, direct relay connections) belongs in Swift; all Nostr relay communication is NMP's responsibility. (Previously: PeerMessageRecord needs tags (Vec<Vec<String>>) and raw JSON to restore NIP-10 root resolution and delegation routing in NostrRelayService.handle. <!--  -->, superseded — see nostr-rust-ffi.)
