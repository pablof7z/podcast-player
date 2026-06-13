---
title: Episode Summary
slug: episode-summary
topic: data-persistence
summary: "EpisodeSummary has a SummarySource enum with cases: .llm, .publisherDescription, and .unavailable"
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
---

# Episode Summary

## EpisodeSummary

Episode summarization moved to the Rust kernel LLM pipeline; the summary field is persisted on Episode and survives feed refreshes/restarts. EpisodeSummary has a SummarySource enum with cases: .llm, .publisherDescription, and .unavailable. Tool result JSON includes a summary_source field so the LLM can distinguish when text is a publisher-provided blurb rather than an AI-generated summary.

<!-- citations: [^0f3f2-35] [^14943-8] -->
