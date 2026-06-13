---
title: Nostr Transcript Publishing
slug: nostr-transcript-publishing
topic: nostr-protocol
summary: The sign and publish logic for transcript events must be copied from NostrCommentService.publish (lines 207-280), which reads Settings.nostrRelayURL, handles NI
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:9f2d26f1-3e71-46b0-83d8-cc9895be3a8e
  - session:d0447a6c-e8a4-4913-a5bd-cd462c96487a
  - session:f3b466c6-7791-44b3-b004-aae2066a9019
  - session:c43d5e77-d667-4e71-a574-47aaab5b6a7a
  - session:rollout-2026-05-26T09-10-44-019e62e8-3112-7080-98ca-48ac46d8b8d2
---

# Nostr Transcript Publishing

## Sign & Publish Logic

Publishing must actually sign and broadcast events to relays, not return relay_pending without signing or broadcasting. (Previously: Publishing Nostr events uses nmp.publish with PublishTarget::Auto (or PublishRaw for unsigned content); NMP signs with the active signer and routes through its relay pool, superseded — see nip74-episode-events.) Publishing must sign and broadcast events to relays, not return `relay_pending` without signing. Author claims (kind:10064), comments (kind:1111), and agent notes (kind:1) are published via PublishRaw through NMP with the active signer; no app-side signing or relay URL specification. (Previously: logic was copied from NostrCommentService.publish which reads Settings.nostrRelayURL, handles NIP-42 AUTH, and OK-ack timeouts.) FeedbackRelayClient must not be used for publishing transcripts because it is hardcoded to tenex.chat. NostrPodcastPublisher.publishShow and publishEpisode both return String (the signed event ID) instead of void.

The app connects to Nostr relays once and lets NMP drive all relay routing automatically; the app must not specify relay URLs at publish or subscribe time. (Previously: V1 publishes transcripts to a single relay configured via the Settings.nostrRelayURL string; there is no multi-relay setting, superseded — see nostr-rust-ffi.)

Transcript publishing must be gated on explicit opt-in or UserIdentityStore.hasIdentity to prevent a cold-launch signer race where a publish triggered in the first approximately 1 second could use an auto-generated disposable key.

PublishError.encodingFailed and .relayAckTimeout are retained for source compatibility but no longer fire; Rust-side errors map to .relayRejected.

<!-- citations: [^f3b46-22] [^9f2d2-1] [^9f2d2-2] [^9f2d2-3] [^d0447-5] [^c43d5-10] [^rollo-229] -->
## Event Identification & Filtering

A stable cross-instance ID for transcript events should reuse CommentTarget.nip73Identifier using the pattern "podcast:item:guid:\(guid)". Synthetic GUIDs (prefixed with synth::) must be filtered out when identifying transcripts for Nostr events. <!-- [^9f2d2-4] -->


NostrPodcastDiscoveryService episodes lack publishedAt (falls back to createdAt), per-episode imageUrl (falls back to nil), and transcript MIME type (arrives untyped through FFI). <!-- [^f3b46-21] -->
## Subscription Model

The subscription pattern for consuming transcript events should copy the NostrCommentService session model (lines 50-199) rather than NostrRelayService (which is a hardcoded agent inbox). <!-- [^9f2d2-5] -->

## Payload Size & Blossom Upload

Typical 60-minute transcripts are 100-500 KB and 2-hour transcripts are approximately 1 MB, making inline publishing to Nostr unviable for most public relays which reject events larger than 64-256 KB. NMP v0.6.0 provides nmp-blossom (typed upload action with sign+transport, supporting both nsec and NIP-46 bunker), dissolving the two biggest blockers for Blossom kernel upload and social-graph trust gating, so the Blossom-URL-in-Nostr-event wiring is no longer net-new. (Previously: For larger transcripts, JSON must be uploaded to Blossom and a URL plus sha256 placed in the Nostr event; BlossomUploader exists for profile photos but the Blossom-URL-in-Nostr-event wiring is net-new. <!--  -->, superseded — see nmp-version-upgrades.)

## Settings UI

Settings UI for transcript publishing should be added as a row in TranscriptsSettingsView under Intelligence. AgentAccessControlView (Allowed/Pending/Blocked tabs with avatar rows and BlockPeerSheet) should be used as a turnkey template for the transcript pubkey blocking UI. Pubkey-to-profile lookup for blocked transcript publishers should use store.state.nostrProfileCache and NostrProfileFetcher. <!-- [^9f2d2-7] -->

## Blocking Design Decision

AppState.nostrBlockedPubkeys already exists for dropping agent-DM events from blocked pubkeys; a design decision is needed on whether to reuse this single combined blocklist or create a separate nostrBlockedTranscriptPublishers list where blocked from transcripts is distinct from blocked from DMing an agent. <!-- [^9f2d2-8] -->
