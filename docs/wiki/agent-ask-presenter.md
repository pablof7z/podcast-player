---
title: Agent Ask Presenter
slug: agent-ask-presenter
topic: agent-system
summary: AgentAskPresenter supports only typed text input for the ask sheet; the voice-answer (STT) path is deferred.
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
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
---

# Agent Ask Presenter

## Input Modes

AgentAskPresenter supports only typed text input for the ask sheet; the voice-answer (STT) path is deferred. <!-- [^0f3f2-1] -->

Agent entry points must be consolidated into a single `AgentRoute` path, with Search's "Ask the agent" no-results CTA passing the query via `podcastr://agent?draft=...` or a store-level pending draft. <!-- [^rollo-96] -->
