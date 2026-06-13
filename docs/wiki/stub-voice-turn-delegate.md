---
title: Stub Voice Turn Delegate
slug: stub-voice-turn-delegate
topic: agent-system
summary: StubVoiceTurnDelegate echoes user speech word-by-word with a 0.6s delay instead of using an LLM
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-13
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
---

# Stub Voice Turn Delegate

## Echo Behavior

StubVoiceTurnDelegate echoes user speech word-by-word with a 0.6s delay instead of using an LLM. It falls back to this behavior when turnDelegate is nil, blocked on the AgentChatSession adapter (Lane 10). <!-- [^0f3f2-66] -->

ApplesSpeechDetector always returns true with no real VAD classification; barge-in is gated by energy only. <!-- [^0f3f2-67] -->

VoiceTurnDelegate TODO requires the adapter to pass source: .voiceMessage. <!-- [^0f3f2-68] -->
