---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: architecture
status: active
subjects:
  - ollama-config
  - local-llm
  - model-discovery
supersedes: []
related_claims: []
source_lines:
  - 1111-1159
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Ollama configuration must flow through all paths, including keyless local

## Prior State

Only the chat session used the configurable Ollama URL; relay bridge, memory compiler, picks service, and inbox triage all used the hardcoded default. Model discovery always hit ollama.com. API key was required even for local keyless instances.

## Trigger

Prior partial fix (Ollama endpoint in Settings) left 4 of 5 call sites and model discovery still hardcoded; audit flagged these as caveats.

## Decision

All 5 streamCompletion call sites now pass URL(string: store.state.settings.ollamaChatURL). OllamaModelCatalogService derives /api/tags from the configured base URL. LLMProviderCredentialResolver.requiresAPIKey(for:ollamaChatURL:) centralizes cloud-vs-local (ollama.com requires key; other hosts optional). AgentOllamaClient skips Authorization header when key is empty.

## Consequences

- Local Ollama users can point all agent paths at their instance without a dummy key
- Model discovery works against the configured host, not hardcoded ollama.com
- ShowDetailView now shows an error alert on subscribe failure instead of only a haptic

## Open Tail

- AgentChatTitleGenerator still uses WikiOpenRouterClient internally — no Ollama path to fix

## Evidence

- transcript lines 1111-1159

