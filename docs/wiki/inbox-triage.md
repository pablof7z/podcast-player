---
title: Inbox Triage
slug: inbox-triage
summary: Inbox triage uses a local LLM (Ollama) to assign a priority_score, reason, and categories to each unlistened podcast episode.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
  - session:2a627da2-be7e-41cb-968e-79e23db03c36
---

# Inbox Triage

## Overview

Inbox triage must be redesigned from first principles as an agent that prioritizes the user's inbox with full context of the user's preferences. Per-episode LLM triage calls without user-preference context produce irrelevant results and must not be used. (Previously: Inbox triage used a local LLM (Ollama) to assign a priority_score, reason, and categories to each unlistened podcast episode.) The LLM endpoint for inbox triage must be read from the settings store rather than being hardcoded to localhost:11434.

<!-- citations: [^67062-1] [^67062-6] -->
## Trigger & Scheduling

A 10-minute cooldown (TRIAGE_RETRY_COOLDOWN_SECS) suppresses proactive re-triggering after a pass.

<!-- citations: [^67062-2] [^2a627-1] [^67062-8] -->
## LLM Invocation & Failure Handling

When an episode has no triage cache entry, the system enqueues it for a background triage pass. On startup, all untrialed episodes receive a Pending cache entry with attempted_at timestamp, preventing re-enqueue until the cooldown elapses. The system prompt instructs the LLM to output only structured JSON with fields priority_score (0.0–1.0), priority_reason (one sentence), and categories (array of tags). The per-episode triage payload includes the podcast title, episode title, and first 500 characters of the episode description. When a triage call fails, the app stamps a Pending placeholder in the cache with attempted_at set to the current time.

<!-- citations: [^67062-3] [^2a627-2] [^67062-7] -->
## Heuristic Fallback

When LLM triage is unavailable, a heuristic fallback using recency buckets (Just published, Recent, This week) is used for inbox display. [^67062-4]
## See Also

