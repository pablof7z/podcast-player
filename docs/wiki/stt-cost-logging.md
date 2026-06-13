---
title: STT Cost Logging
slug: stt-cost-logging
topic: stt-providers
summary: STT cost logging exists for AssemblyAI (real USD cost + audio seconds), ElevenLabs Scribe (duration from last word timestamp), and OpenRouter Whisper (duration
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-11
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
---

# STT Cost Logging

## STT Cost Logging

STT cost logging exists for AssemblyAI (real USD cost + audio seconds), ElevenLabs Scribe (duration from last word timestamp), and OpenRouter Whisper (duration from verbose_json). UsageRecord includes an optional `audioDurationSeconds` field, and the Recent Calls row renders it as formatted audio duration when present. <!-- [^7f076-9] -->
