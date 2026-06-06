---
title: Inbox Triage
slug: inbox-triage
summary: Inbox triage sends all needy episodes in a single user message to the agent, not in chunked batches
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-04
updated: 2026-06-04
verified: 2026-06-04
compiled-from: conversation
sources:
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
---

# Inbox Triage

## Overview

Inbox triage sends all needy episodes in a single user message to the agent, not in chunked batches. The triage agent receives a user message listing new episodes since the last triage, asking the agent to prioritize the inbox using the user's memory facts. On cold start (empty memory and history), the triage agent is not invoked and the recency heuristic is used instead. <!-- [^67062-1] -->

## System Prompt and Backend

Inbox triage uses the same agent identity and memory as the chat agent, via `build_system_prompt_with_memory`, with a triage-specific task instruction appended. `build_system_prompt_with_memory` and `AGENT_SYSTEM_PROMPT` move from `agent_handler.rs` to `agent_llm.rs` as `pub(crate)` so both chat and triage paths share them. Triage inherits `backend_for` routing (Ollama/OpenRouter/LocalModel) automatically via `single_turn`, with no manual client construction.

<!-- citations: [^67062-2] [^67062-8] -->
## Tool Set

The triage tool set includes `get_memory_facts`, `search_library`, and `set_episode_priorities` but excludes transcript tools and `get_podcast_info`. `set_episode_priorities` is a batch-write tool that takes an array of `{episode_id, score, reason, categories}` in a single tool call rather than per-episode writes.

<!-- citations: [^67062-3] [^67062-9] -->
## Execution

`run_background_agent_task` is a wrapper around the tool loop with empty conversation history, `TRIAGE_TOOL_INSTRUCTIONS`, and `MAX_TRIAGE_TOOL_TURNS = 6`. The conversation transcript is structurally isolated from the background agent task and is not a parameter to `run_background_agent_task`. After a triage pass, any episode still missing a fresh `Ready` entry in the cache gets stamped `Pending` via `reconcile_pending` to prevent hot-spawn loops that bypass the cooldown guarantee.

<!-- citations: [^67062-4] [^67062-10] -->
## User Message Format

The triage user message format includes episode_id, podcast title, episode title, and published date for each needy episode. <!-- [^67062-5] -->
