---
title: AI Chapters Pipeline
slug: ai-chapters-pipeline
summary: AI chapters use a typed retry ladder (Ollama structured output with monotonicity + bounds validation) and persist to Rust
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-31
updated: 2026-06-01
verified: 2026-05-31
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# AI Chapters Pipeline

## Chapter Generation Pipeline

AI chapters use a typed retry ladder (SynthError::Unavailable vs SynthError::Parse) with a 45-second timeout, and leave episodes chapterless on terminal parse failure rather than fabricating confidence. The pipeline employs a fallback ladder: publisher chapters always win; if none, LLM-generated chapters are carried forward; if LLM fails, equal-length stubs are the last resort. The `handle_index_episode` function clears stale chunks before upserting new ones to prevent stale knowledge accumulation.

<!-- citations: [^14943-100] [^14943-101] [^14943-134] -->
