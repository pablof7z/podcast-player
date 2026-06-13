---
title: LLM Backend Abstraction
slug: llm-backend-abstraction
topic: agent-system
summary: "The Rust LLM backend abstraction is built around an `LlmBackend` trait, annotated with `async_trait`, with the signature `async fn complete(&self, system: &str,"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-12
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
---

# LLM Backend Abstraction

## LLM Backend Abstraction

The Rust LLM backend abstraction is built around an `LlmBackend` trait, annotated with `async_trait`, with the signature `async fn complete(&self, system: &str, history: &[Message], user: &str) -> Result<String, String>`. All eight `*_llm.rs` files route through `backend_for()` in `factory.rs` rather than hardcoding `ollama::Client`, using `Box<dyn LlmBackend>` for FFI-boundary dispatch. <!-- [^4dd36-1] -->

## Backend Implementations

The `LlmBackend` trait has three concrete implementations: `OllamaBackend`, `OpenRouterBackend`, and `LocalModelBackend`. The `local_model_id: Option<String>` field in the Rust store/settings projects through the snapshot, and `factory.rs` checks it first — if set, `LocalModelBackend` wins over OpenRouter and Ollama. <!-- [^4dd36-2] -->

## Provider Credentials

The Rust `factory.rs` reads provider credentials from the `PodcastStore` accessors (`open_router_api_key`, `ollama_api_key`) rather than using stub functions that return `None`. <!-- [^4dd36-3] -->

## Swift FFI Integration

Swift has zero provider awareness of LLM routing. `AgentOpenRouterClient.swift` and `AgentOllamaClient.swift` are deleted, and `AgentLLMClient.swift` is rewritten as a thin FFI shim that calls the Rust kernel. Swift simply renders streamed tokens without knowing what provider handles the request. <!-- [^4dd36-4] -->

## Extensibility

The `LlmBackend` trait is the correct seam for adding future backends like Gemma4. The `complete_for_role` LLM dispatch helper consolidates six duplicated LLM dispatch blocks and three `extract_json` copies into one helper with a `resolve_request` seam for timeout-wrapped callers, eliminating per-caller boilerplate. Timing sleeps, hard-coded clients, real URLSession/NWPathMonitor paths, and static agent/history clients are replaced with injectable interfaces for deterministic testing.

<!-- citations: [^4dd36-5] [^c1691-26] [^rollo-46] [^c1691-57] [^c1691-89] [^c1691-103] [^c1691-118] [^c1691-139] -->
