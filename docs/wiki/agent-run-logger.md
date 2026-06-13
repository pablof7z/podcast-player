---
title: Agent Run Logger
slug: agent-run-logger
topic: agent-system
summary: AgentRunLogger uses do/catch with os.Logger.error for three persistence sites
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

# Agent Run Logger

## Error Handling

AgentRunLogger uses do/catch with os.Logger.error for three persistence sites. (Previously: used try?, which silently swallowed disk/encode errors.) <!-- [^0f3f2-9] -->
