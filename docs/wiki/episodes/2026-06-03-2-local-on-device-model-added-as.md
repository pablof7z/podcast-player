---
type: episode-card
date: 2026-06-03
session: 4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a.jsonl
salience: product
status: superseded
subjects:
  - local-llm-provider
  - litert-lm
  - gemma4-e2b
  - local-model-backend
supersedes: []
related_claims: []
source_lines:
  - 1-23
  - 940-965
  - 1041-1093
  - 1177-1207
captured_at: 2026-06-12T13:08:30Z
---

# Episode: Local on-device model added as first-class LLM provider

## Prior State

Only OpenRouter and Ollama were available as LLM providers, both requiring network access. No on-device inference capability existed. The app routed all AI through Ollama at localhost:11434 or OpenRouter cloud, requiring the user to have a running server or internet connection.

## Trigger

User asked about embedding Gemma4 locally inside the podcast iPhone app. Research revealed MediaPipe LLM Inference is deprecated; Google's current path is LiteRT-LM with native Swift APIs and Metal GPU acceleration. The prior LlmBackend migration made adding a third provider architecturally clean.

## Decision

Added 'local' as a third first-class provider via LiteRT-LM (SPM 0.12.0) with a reverse-FFI callback pattern: Swift registers an inference callback at startup, Rust's LocalModelBackend calls it when local is selected. User must explicitly opt in by going to Settings → AI → Local Models and downloading a model. No silent cloud fallback when local is selected — LlmError::Unavailable is returned instead. Catalog initially ships Gemma4-E2B (2.58GB) and Gemma4-E4B, both pinned to HuggingFace commit SHAs.

## Consequences

- LLMProvider.swift gains .local case alongside .openRouter and .ollama
- LocalModelBackend in Rust returns LlmError::Unavailable when no callback is registered (no silent cloud fallback — respects user's deliberate provider choice)
- LocalLLMService is a Swift actor that serializes inference, uses real LiteRT-LM SDK (not stubbed), direct async/await (no DispatchSemaphore on cooperative threads)
- LocalModelDownloadManager implements notDownloaded → downloading(progress) → downloaded → active state machine with URLSession on OperationQueue.main
- Settings UI shows Local Models as a peer provider option with download button, progress indicator, and active badge
- Local model ID projects through the full Rust store → SettingsSnapshot → Swift UI chain (not UserDefaults)
- Gemma4-E2B download is ungated (no auth required), plain URLSession, from HuggingFace litert-community org

## Open Tail

- LiteRT-LM Swift API is Early Preview — API could shift before GA
- Device testing needed — iPhone 17 Pro benchmark numbers (2,878 tk/s GPU prefill) won't translate 1:1 to older devices
- gemma4-e4b download URL pins to resolve/main/ not a SHA — reproducibility risk

## Evidence

- transcript lines 1-23
- transcript lines 940-965
- transcript lines 1041-1093
- transcript lines 1177-1207

