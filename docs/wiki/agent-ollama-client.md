---
title: Agent Ollama Client
slug: agent-ollama-client
topic: agent-system
summary: "AgentOllamaClient.chatURL defaults to https://ollama.com/api/chat, which is the correct default for the Ollama cloud service."
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
  - session:2a627da2-be7e-41cb-968e-79e23db03c36
  - session:rollout-2026-05-09T14-56-23-019e0c98-8803-7ef0-b7a2-bf0b605a2360
  - session:rollout-2026-05-26T10-25-30-019e632c-a2ae-7783-b58a-24f557011da1
---

# Agent Ollama Client

## Default Endpoint

AgentOllamaClient.swift is deleted, and AgentLLMClient.swift is rewritten as a thin FFI shim that calls the Rust kernel, so there is no AgentOllamaClient.chatURL default in Swift. (Previously: AgentOllamaClient.chatURL defaults to https://ollama.com/api/chat, which is the correct default for the Ollama cloud service. <!--  -->, superseded — see llm-backend-abstraction.)

The chat URL is editable from the providers screen under Ollama settings. <!-- [^0f3f2-4] -->

## User-Configured URL Propagation

AgentLLMClient.swift is rewritten as a thin FFI shim calling the Rust kernel, and all LLM routing goes through factory.rs's backend_for() rather than Swift-side streamCompletion call sites passing ollamaChatURL. (Previously: All five AgentLLMClient.streamCompletion call sites pass the user-configured ollamaChatURL setting, including relay bridge, memory compiler, picks service, and InboxTriageService. (Previously, only the interactive chat session path picked up the user setting; the other three callers used the default URL.) <!--  -->, superseded — see llm-backend-abstraction.)

## Model Discovery Endpoint

OllamaModelCatalogService accepts a chatURL init param and derives /api/tags by replacing /chat at the path tail, with scheme://host/api/tags as fallback. (Previously, the 'Check Available Models' button hit a hardcoded https://ollama.com/api/tags, causing model discovery to break for local Ollama users.) <!-- [^0f3f2-6] -->

## Rust Kernel URL Resolution

The Rust kernel reads the Ollama chat URL from the settings store at call time instead of using a hardcoded localhost constant. inbox_llm.rs was gutted to only contain TriageResult and TriageStatus types; all LLM calling code was removed, and both chat and triage share the agent tool loop via run_background_agent_task in agent_llm.rs. (Previously: Both `triage_episode` (inbox_llm.rs) and `chat_with_tools` (agent_llm.rs) accept a base URL parameter derived from the stored chat URL, superseded — see inbox-triage.) All *_llm.rs files route through backend_for() in factory.rs using Box<dyn LlmBackend> for FFI-boundary dispatch, replacing the old base_url_from_chat_url() URL-stripping approach. (Previously: A helper function `base_url_from_chat_url()` in agent_llm.rs strips the `/api/chat` suffix from the stored full URL to produce the base URL that rig-core expects, superseded — see llm-backend-abstraction.) Swift Settings.swift derives its defaults from SettingsSnapshot() at runtime rather than maintaining an independent Codable defaultOllamaChatURL. (Previously: When the store has an empty chat URL (old data), the default fallback is `https://ollama.com` (the cloud endpoint), matching Swift's `Settings.defaultOllamaChatURL`. <!--  -->, superseded — see podcast-app-state.)

## Ollama Cloud Provider Support

Ollama Cloud is supported as an alternative LLM provider to OpenRouter, with per-role model selection so the user can mix and match providers across different LLM roles. Model selection pulls available models from both OpenRouter and Ollama Cloud for the user to select. Ollama model references use an 'ollama:' prefix while existing plain model IDs default to OpenRouter, maintaining backward compatibility. The optional reranker still uses the existing OpenRouter/Cohere path because Ollama does not expose a rerank endpoint. <!-- [^rollo-3] -->

## Authentication

Ollama Cloud API keys are stored in Keychain. Ollama Cloud model listing via /api/tags is fetched publicly without auth, with Bearer auth added only when an API key exists. <!-- [^rollo-4] -->

## Model Discovery

The model browser merges OpenRouter catalog results with Ollama Cloud /api/tags when an Ollama key is present. Ollama Cloud is pinned in the model provider filter menu so it is not buried by high-count OpenRouter providers. <!-- [^rollo-5] -->

## Embeddings

Local embedding for RAG uses Core ML with all-MiniLM-L6-v2 producing 384-dim vectors, and the vector index contract is migrating from 1024-d to 384-d. (Previously: Ollama embeddings must return 1024-d vectors matching the existing vector index contract, or the client fails clearly rather than corrupting the sqlite-vec index. <!--  -->, superseded — see local-embedding-rag.)

## Salvage Scope

The Ollama local-provider salvage work must target only the Ollama/settings/model-provider files needed for that feature and must not carry old planning files, Android deletions, or unrelated old-App churn. PR #95 merged as commit `d06c39a4` and the salvage scope stayed limited to Ollama/provider/settings/agent call-site files plus `LLMProviderTests` and `whats-new.json`. <!-- [^rollo-256] -->
