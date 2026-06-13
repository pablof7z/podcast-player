---
title: Agent Friend Delegation
slug: agent-friend-delegation
topic: agent-system
summary: "The agent-friend delegation pattern mirrors TenX's `delegate` tool: the agent publishes an event, marks pending external work, and is automatically re-invoked w"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:9f3b9a0a-d40b-4658-ad51-c157a7780612
  - session:rollout-2026-05-09T14-56-23-019e0c98-8803-7ef0-b7a2-bf0b605a2360
---

# Agent Friend Delegation

## Overview

The agent has a TENEX-compatible `delegate(recipient, prompt)` tool that returns a delegation event ID, emits/audits the delegation, and stops the agent's turn. The agent-friend delegation pattern mirrors TenX's `delegate` tool: the agent publishes an event, marks pending external work, and is automatically re-invoked when the response arrives.

<!-- citations: [^9f3b9-1] [^rollo-2] -->
## Sending a Friend Message

When an agent sends a friend message via `send_friend_message`, it publishes a root kind:1 Nostr event (no e-tags) with a p-tag of the friend agent's pubkey. The `publishFriendMessage` function always publishes friend messages as root events with no e-tags; the e-tag threading from `peerContext` was a bug that has been fixed. The `send_friend_message` tool returns a re-invocation notice telling the agent it will be automatically resumed when the other agent responds. <!-- [^9f3b9-2] -->

## Pending Friend Message Model

`PendingFriendMessage` is a `Codable`, `Identifiable`, `Sendable` struct with fields `sentEventID`, `friendPubkey`, `sentAt`, and `origin`, where `origin` is `PendingFriendMessageOrigin` (`.inAppChat(conversationID:)` or `.nostrPeer(rootEventID:peerPubkey:)`). The origin is determined by `deps.chatConversationID` (→ `.inAppChat`) or `deps.peerContext` (→ `.nostrPeer`); these fields are mutually exclusive in practice. `AppState.pendingFriendMessages` holds the list of pending friend messages, decoded with `decodeIfPresent` defaulting to an empty array. Pending friend messages are swept after a 7-day TTL on register and claim operations. <!-- [^9f3b9-3] -->

## Pending Message Registration and Claims

`AppStateStore+FriendMessages` provides `registerPendingFriendMessage(_:)` (appends and sweeps expired), `claimPendingFriendMessage(forRootEventID:)` (removes and returns matching entry), and `hasPendingFriendMessage(forRootEventID:)` (non-mutating check). `PendingFriendMessageRegistrarProtocol` is a `Sendable` protocol with a single `register(_:)` async method; `LivePendingFriendMessageRegistrar` is an `@unchecked Sendable` class that implements it by dispatching to `AppStateStore.registerPendingFriendMessage` on `MainActor`. `LivePodcastAgentToolDeps.make()` wires up `pendingRegistrar` as `LivePendingFriendMessageRegistrar(store: store)`. `PodcastAgentToolDeps` includes a `pendingRegistrar` field of type `(any PendingFriendMessageRegistrarProtocol)?`, threaded through `init`, `withPeerContext()`, and `withChatConversationID()`. <!-- [^9f3b9-4] -->

## Inbound Response Routing

`NostrRelayService.handle()` checks whether an inbound event's NIP-10 root matches a pending friend message BEFORE the allowlist gate, routing matching events directly to the agent responder. NostrAgentResponder passes rootID and inbound.eventID to AgentRelayBridge.reply, which builds a PeerConversationContext and calls withPeerContext before dispatching—replacing the previous flow that claimed pending friend messages, marked inbound events as responded, and dispatched to handleDelegationResponse. (Previously: `NostrAgentResponder.process()` claims the pending friend message by `rootID` before the in-flight check, marks the inbound event as responded, and dispatches to `handleDelegationResponse`. <!--  -->, superseded — see episode-generation-source.)

## Delegation Re-invocation

When the friend agent responds, the app detects the response as a delegation response and immediately re-invokes the original agent in the original context (in-app chat or Nostr peer conversation) with the friend's reply included, headlessly and without requiring UI interaction. For `.inAppChat` delegation responses, the system creates a headless `AgentChatSession` with `resumeWindow: 0`, switches to the original conversation, injects the friend's reply as a user message via `send()`, and persists to `ChatHistoryStore.shared`. For .nostrPeer delegation responses, AgentRelayBridge.reply now accepts rootEventID and inboundEventID parameters, builds a PeerConversationContext, and calls withPeerContext before dispatching—replacing the previous flow where the system separately fetched the peer thread, built message history, injected the delegation response, and then called a parameter-less reply(). (Previously: For `.nostrPeer` delegation responses, the system fetches the original peer thread, builds message history, injects the delegation response, runs `AgentRelayBridge.reply()`, and signs and publishes the reply back into the original Nostr peer conversation, superseded — see episode-generation-source.) After a headless `AgentChatSession` completes a delegation re-invocation for an in-app chat, a `.agentDelegationDidComplete` notification is posted with the conversation UUID so the UI's `AgentChatSession` can reload messages from `ChatHistoryStore` if the conversation IDs match. <!-- [^9f3b9-6] -->
