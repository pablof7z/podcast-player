---
title: Agent Chat Session
slug: agent-chat-session
topic: agent-system
summary: AgentChatSession+Turns has a zeroed-out token usage fallback
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
  - session:9692d124-a1a0-411c-91f9-9d6ebc0b29b1
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Agent Chat Session

## Token Usage

AgentChatSession+Turns has a zeroed-out token usage fallback. AgentAPIResponse.tokensUsed is now optional; run log UI shows a dash instead of fake 0→0 when a provider omits usage data, and a .info log names the model. <!-- [^0f3f2-2] -->

## Scroll Behavior

AgentChatTranscriptView scrolls to the bottom on appear using .onAppear with proxy.scrollTo(lastMessageID, anchor: .bottom). <!-- [^9692d-1] -->

## Android Agent Operations

Agent chat on Android dispatches podcast.agent ops (send/clear) through ActionDispatcher; the kernel runs a real LLM tool-calling loop (not canned replies). <!-- [^c1691-261] -->
