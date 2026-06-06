---
title: Local LLM Service
slug: local-llm-service
topic: local-llm-service
summary: The `LocalLLMService` manages the lifecycle of the on-device engine by loading it when a local model is selected and ensures the engine is loaded via an idempot
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-05
updated: 2026-06-05
verified: 2026-06-05
compiled-from: conversation
sources:
  - session:e1ab0629-64bc-4383-bd22-c0843ca16a99
---

# Local LLM Service

## LocalLLMService

The `LocalLLMService` manages the lifecycle of the on-device engine by loading it when a local model is selected and ensures the engine is loaded via an idempotent `ensureLoaded` method. It handles prompt-shape normalization to ensure the Swift side correctly parses the JSON payload (containing system, history, and user fields) sent by the Rust backend. <!-- [^e1ab0-1] -->

## LLM Factory Routing

The LLM factory uses a gate to check if the configured model has a `local:` prefix; if so, it routes to the local backend, otherwise it falls back to the hardcoded cloud constant. <!-- [^e1ab0-2] -->
