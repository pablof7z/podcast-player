---
title: Live Wiki Storage Adapter
slug: live-wiki-storage-adapter
topic: wiki-generation
summary: LiveWikiStorageAdapter uses Settings() default for wikiModel instead of an inlined 'openai/gpt-4o-mini' literal
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

# Live Wiki Storage Adapter

## Model Configuration

LiveWikiStorageAdapter uses Settings() default for wikiModel instead of an inlined 'openai/gpt-4o-mini' literal. (Previously: it fell back to hardcoded model 'openai/gpt-4o-mini' when the store was unavailable.) <!-- [^0f3f2-46] -->
