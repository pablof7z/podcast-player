---
title: Ollama LLM Configuration
slug: ollama-llm-configuration
summary: "Ollama runs at localhost:11434 with models deepseek-v4-flash:cloud and deepseek-v4-pro:cloud."
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-03
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
  - session:2a627da2-be7e-41cb-968e-79e23db03c36
  - session:4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
---

# Ollama LLM Configuration

## Ollama LLM Configuration

The Rust kernel reads the Ollama base URL from the `ollama_chat_url` setting in the store instead of using a hardcoded `localhost:11434` constant. The `triage_episode` function accepts a `base_url` parameter derived from this stored setting, and `chat_with_tools` reads the URL from the store and passes it through to `single_turn`. A `base_url_from_chat_url()` helper strips `/api/chat` from the stored full URL to produce the base URL expected by rig-core. When the store has an empty `ollama_chat_url` value, the system falls back to the cloud endpoint `https://ollama.com`. Note that on a physical iPhone, `localhost:11434` cannot reach Ollama running on the Mac. The app must support OpenRouter as an LLM provider in addition to Ollama and any local model.

<!-- citations: [^14943-123] [^67062-5] [^2a627-3] [^4dd36-7] -->
