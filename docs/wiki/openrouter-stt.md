---
title: OpenRouter STT
slug: openrouter-stt
topic: stt-providers
summary: OpenRouter STT returns text-only transcripts with no segment timestamps, making it fundamentally incompatible with AIChapterCompiler.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-12
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
---

# OpenRouter STT

## Transcript Format & Compatibility

AIChapterCompiler uses a dedicated chapterCompilationModel setting (default openai/gpt-4o-mini) to compile chapters from transcript text via LLM, so it does not require segment timestamps from STT providers and OpenRouter STT's text-only output is compatible. (Previously: OpenRouter STT returns text-only transcripts with no segment timestamps, making it fundamentally incompatible with AIChapterCompiler. <!--  -->, superseded — see ai-chapter-compiler.)
