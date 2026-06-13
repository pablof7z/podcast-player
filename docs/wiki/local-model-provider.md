---
title: Local Model Provider
slug: local-model-provider
topic: agent-system
summary: The local model provider is not enabled by default
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
  - session:e1ab0629-64bc-4383-bd22-c0843ca16a99
  - session:56e47844-b4ff-4402-9528-c704eade1d7b
---

# Local Model Provider

## Overview

The local model provider is not enabled by default. The user must explicitly go to the AI providers settings screen, select Local Models, and download a model before it becomes available. The local models UI accommodates choosing from multiple models rather than assuming a single model, with an extensible `LocalModelCatalog` containing at least Gemma4-E2B and Gemma4-E4B. <!-- [^4dd36-13] -->

## Model Architecture and API Status

LiteRT-LM (Google's current path for on-device Gemma) replaces the deprecated MediaPipe LLM Inference for mobile deployment. The E-variant models (E2B, E4B) are architecturally leaner MatFormer builds, not just quantized versions of the full models. AgentOpenRouterClient.swift and AgentOllamaClient.swift are deleted, and AgentLLMClient.swift is rewritten as a thin FFI shim that calls the Rust kernel, removing Swift's direct dependency on the LiteRT-LM Swift API. (Previously: The LiteRT-LM Swift API is in Early Preview status, meaning the API surface could shift before general availability. <!--  -->, superseded — see llm-backend-abstraction.)

Only one on-device model engine can be loaded at a time; selecting different local models for two roles loads only the first. <!-- [^e1ab0-12] -->

Swift has zero provider awareness of LLM routing; cloud-to-cloud per-role model dispatch is handled by the Rust kernel rather than by hardcoded constants in Swift. (Previously: Cloud-to-cloud per-role routing still uses hardcoded constants (e.g, superseded — see llm-backend-abstraction.) GPT-4 for wiki); only the local: prefix is dynamically routed. <!-- [^e1ab0-13] -->

effectiveLocalModelID is scoped to roles that actually have a wired local call site (agent initial, agent thinking, wiki, categorization, chapters), excluding memory/embeddings which would load an unused engine. <!-- [^e1ab0-14] -->

The local engine is loaded/unloaded reactively via syncLocalEngine on settings change and at kernel-attach startup, keyed off effectiveLocalModelID. <!-- [^e1ab0-15] -->

The LLM client is dispatched via backend_for(store, model) which routes to Ollama, OpenRouter, or LocalModelBackend based on settings, eliminating the role_model_or_default local-prefix check and cloud-default-constant fallback in Swift. (Previously: Per-role model selection routes local models through role_model_or_default, which returns the configured model only if it has a local: prefix, otherwise falling back to the cloud default constant (zero regression to cloud behavior). <!--  -->, superseded — see llm-provider-credential-resolver.)

LocalLLMService.infer rejects inference requests that specify a different model than the one currently loaded. <!-- [^e1ab0-17] -->

LocalLLMService.ensureLoaded is serialized to prevent race conditions on concurrent loads. <!-- [^e1ab0-18] -->

The ad-hoc fallback that retried the 'Agent (Thinking)' role on local model failure is removed, so a failed local model surfaces its real error directly. <!-- [^56e47-5] -->

After launch, the local model engine takes ~minutes to load; sending a message instantly may briefly show 'Local model not loaded' before the engine is ready. <!-- [^56e47-6] -->

Concurrent peer agents reinstalling their own builds on the physical device can overwrite a correctly-entitled build with one lacking the entitlement, causing the mmap failure to recur. <!-- [^56e47-7] -->
