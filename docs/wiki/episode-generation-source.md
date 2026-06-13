---
title: Episode Generation Source
slug: episode-generation-source
topic: agent-system
summary: "Episode.GenerationSource is a nested enum with cases .inAppChat(conversationID: UUID) and .nostr(rootEventID: String, peerPubkeyHex: String)"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-12
updated: 2026-06-12
verified: 2026-05-12
compiled-from: conversation
sources:
  - session:514d3552-fbf6-4382-9488-8ba8b4289797
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Episode Generation Source

## GenerationSource Enum

Episode.GenerationSource is a nested enum with cases .inAppChat(conversationID: UUID) and .nostr(rootEventID: String, peerPubkeyHex: String). It uses manual Codable with a type discriminator key for safe encode/decode of associated values. <!-- [^514d3-1] -->

## Episode Storage

Episode has an optional generationSource field of type GenerationSource?, decoded with decodeIfPresent for backward compatibility. <!-- [^514d3-2] -->

## Service Layer Propagation

AgentGeneratedPodcastService.publishEpisode accepts an optional generationSource parameter (default nil) and sets it on the created Episode. TTSPublisherProtocol.generateAndPublish includes a generationSource parameter, and AgentTTSComposer.generateAndPublish accepts and forwards it. <!-- [^514d3-3] -->

## Dependency Context Threading

PodcastAgentToolDeps has a chatConversationID: UUID? field and a withChatConversationID(_:) method. AgentTools+TTS.generateTTSEpisodeTool builds an Episode.GenerationSource from deps.peerContext or deps.chatConversationID. AgentChatSession+Turns passes podcastDeps?.withChatConversationID(currentConversationID) instead of the raw podcastDeps when dispatching AgentTools. <!-- [^514d3-4] -->

## Nostr Context Threading

AgentRelayBridge.reply accepts rootEventID: String? and inboundEventID: String? parameters, builds a PeerConversationContext, and calls withPeerContext before dispatching. NostrAgentResponder passes rootID and inbound.eventID to AgentRelayBridge.reply. This fixes the peerContext nil bug in Nostr-triggered podcast generation by threading rootEventID through AgentRelayBridge.reply and calling withPeerContext before dispatch. <!-- [^514d3-5] -->

## Player UI

PlayerGenerationSourceChip is a chip view that displays the generation source for both Nostr and in-app cases, using .glassSurface styling and NotificationCenter for navigation. PlayerView displays a generationSourceChip in the episodeHeader below the downloadBadge when the episode has a generationSource. <!-- [^514d3-6] -->

## Navigation Actions

Tapping the generation source chip for a Nostr-sourced episode opens NostrConversationDetailView for the specific conversation that triggered generation, showing the counterparty's kind:0 profile (avatar + name) as author. Tapping the generation source chip for an in-app chat episode opens the AgentChatView at the specific conversation where the podcast was requested. .openAgentChatConversation is a NotificationCenter notification with a UUID userInfo key for opening a specific in-app chat conversation. RootView handles the .openAgentChatConversation notification by calling agentSession?.switchToConversation(id) and setting showAgentChat to true, likely dismissing the player sheet first. <!-- [^514d3-7] -->

## What's New Entry

The whats-new.json entry for this feature has a timestamp after 2026-05-13T00:20:00Z. <!-- [^514d3-8] -->

## Nostr Episode Fetch

Nostr kind:54 episode fetch (PR #389) registers a NostrEpisodesObserver via OnceLock before opening relay interest, so zero events are dropped during the EOSE sweep. Feedless shows use UUIDv5-based PodcastIds derived from pubkey. <!-- [^c1691-1] -->

## Synthetic Episode Registration

Synthetic episode registration moved to the Rust kernel via RegisterSyntheticEpisode; episodes survive the applyKernelState full-replace and are idempotent on episode id. <!-- [^14943-7] -->
