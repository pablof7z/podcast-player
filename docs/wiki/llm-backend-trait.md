---
title: LLM Backend Trait Abstraction
slug: llm-backend-trait
summary: LLM calls require an LlmBackend trait abstraction in Rust, allowing both Ollama and local providers to be passed as &dyn LlmBackend instead of a hardcoded base_
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
---

# LLM Backend Trait Abstraction

## LlmBackend Trait

The Rust kernel has a shared `LlmBackend` trait abstraction that reads the user's configured provider and credentials from the store and routes to the correct backend (Ollama or OpenRouter-compatible). All 8 Rust LLM files swap their hardcoded Ollama client for this shared `LlmBackend` trait. OpenRouter credential fields already exist in the store but are completely unused by any Rust LLM call. Swift dispatches to the Rust side without awareness of provider type; Swift is completely unaware of `LLMProvider`, `OpenRouterCredentialStore`, or `AgentOpenRouterClient`.

<!-- citations: [^4dd36-1] [^4dd36-9] -->
## See Also

