---
title: Live Episode Summarizer Adapter
slug: live-episode-summarizer-adapter
topic: agent-system
summary: LiveEpisodeSummarizerAdapter returns the raw RSS description when no transcript is available or no LLM key is configured
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
---

# Live Episode Summarizer Adapter

## Fallback Behavior

LiveEpisodeSummarizerAdapter returns the raw RSS description when no transcript is available or no LLM key is configured. Tool result JSON includes a summary_source field so the LLM can distinguish when text is a publisher-provided blurb rather than an AI-generated summary. (Previously: This output is indistinguishable from a real summary. <!--  -->, superseded — see episode-summary.)
