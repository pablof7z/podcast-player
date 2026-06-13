---
title: Briefing Composer
slug: briefing-composer
topic: agent-system
summary: BriefingComposer .thisShow scope throws unsupportedScope unconditionally
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-26
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:rollout-2026-05-11T09-10-31-019e15a8-97f5-7fc2-9daf-4c834d1999b0
---

# Briefing Composer

## Known Issues

BriefingFixtureScript ignores the request parameter in outroBody(for:). LiveBriefingComposerAdapter dropped the discarded style parameter from freeformQuery. The Swift BriefingComposer produces audio briefings (RAG→LLM→TTS→stitch→playable .m4a); the Rust M5 path is text-only, so briefings deletion is blocked on a human decision about which mechanism is canonical. `thisShow` briefings still need a request model that carries a show id before they can generate narrowly.

<!-- citations: [^0f3f2-19] [^14943-4] [^rollo-119] -->

## Composition Rules

Briefing composition uses the real LLM path and only allows fixture fallback when explicitly opted in for tests or previews. Briefing scopes do not silently widen unsupported scoped requests to all content; `thisShow` resolves empty or fails explicitly until the request carries a show id, and `thisWeek` scopes to recent episode ids. <!-- [^rollo-120] -->
