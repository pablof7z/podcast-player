---
type: episode-card
date: 2026-06-03
session: 4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a.jsonl
salience: architecture
status: active
subjects:
  - llm-backend-trait
  - swift-provider-blind
  - nmp-doctrine-enforcement
supersedes: []
related_claims: []
source_lines:
  - 136-153
  - 399-421
  - 423-435
  - 927-939
captured_at: 2026-06-12T13:08:30Z
---

# Episode: Agent LLM routing migrated from Swift to Rust kernel

## Prior State

Swift owned all LLM provider logic: the LLMProvider enum, AgentOpenRouterClient, AgentOllamaClient, credential resolution from Keychain, HTTP calls, and the tool loop. Rust agent_llm.rs existed but was orphaned — Swift's AgentLLMClient.streamCompletion drove everything directly.

## Trigger

While investigating how local Gemma would fit into the architecture, discovered that Swift's entire agent-chat path bypasses Rust completely — AgentChatSession, AgentRelayBridge, AgentMemoryCompiler, AgentPicksService, and NostrAgentResponder all call AgentLLMClient.streamCompletion directly. This violates NMP doctrine (business logic belongs in Rust; Swift is a rendering shell).

## Decision

All LLM routing moves to Rust. New LlmBackend trait with OllamaBackend and OpenRouterBackend implementations, factory.rs reads credentials from the Rust store. Swift's AgentLLMClient rewritten as a 70-line provider-blind FFI shim that calls nmp_app_podcast_chat_complete. AgentOpenRouterClient.swift and AgentOllamaClient.swift deleted entirely. Rust owns when to call, what prompt to send, and what to do with the reply.

## Consequences

- AgentOpenRouterClient.swift and AgentOllamaClient.swift deleted — Swift has zero provider awareness for agent chat
- All 8 *_llm.rs files migrated off direct ollama::Client to the LlmBackend trait
- New FFI entry point nmp_app_podcast_chat_complete drives the full Rust tool loop including tool dispatch
- Swift's AgentLLMClient is now provider-blind — it sends a JSON message array and receives a text string
- Adding a new provider (like local Gemma) now requires only a new LlmBackend implementation + factory branch, no Swift changes
- Credential push chain restored: kernelSetProviderApiKeys wired at all 5 Swift call sites (startup, onboarding×2, ollama settings, openrouter settings)

## Open Tail

*(none)*

## Evidence

- transcript lines 136-153
- transcript lines 399-421
- transcript lines 423-435
- transcript lines 927-939

