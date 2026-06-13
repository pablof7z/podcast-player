---
type: episode-card
date: 2026-06-03
session: 2a627da2-be7e-41cb-968e-79e23db03c36
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/2a627da2-be7e-41cb-968e-79e23db03c36.jsonl
salience: root-cause
status: active
subjects:
  - ollama-url-config
  - inbox-triage
  - agent-llm
supersedes: []
related_claims: []
source_lines:
  - 1-22
  - 128-135
  - 248-270
  - 350-383
  - 514-521
captured_at: 2026-06-12T13:06:27Z
---

# Episode: Rust kernel ignored configured Ollama URL, hardcoded localhost

## Prior State

Both inbox_llm.rs and agent_llm.rs hardcoded http://localhost:11434 as the Ollama base URL via const OLLAMA_BASE_URL. The user-configurable ollama_chat_url stored in the kernel's PodcastStore (defaulting to https://ollama.com/api/chat in Swift) was never read by the LLM call sites. This caused all triage and agent-chat LLM calls on physical iOS devices to fail, because localhost:11434 on the device points to the device itself, not the Mac running Ollama.

## Trigger

User observed that Ollama Cloud endpoint was configured as ollama.com/api/chat in settings, yet the app was hitting localhost:11434. Investigation revealed the Rust kernel had two hardcoded constants (OLLAMA_BASE_URL in inbox_llm.rs and agent_llm.rs) that completely bypassed the stored setting.

## Decision

Removed both hardcoded OLLAMA_BASE_URL constants. Added base_url_from_chat_url() in agent_llm.rs that strips /api/chat from the stored full URL (since rig-core takes a base URL, not the full endpoint). Both triage_episode and chat_with_tools now read ollama_chat_url from the PodcastStore at call time and derive the base URL dynamically. Empty/missing URL falls back to https://ollama.com (cloud), matching Swift's default.

## Consequences

- On-device inbox triage and agent chat now use the user's configured Ollama URL instead of always hitting localhost
- Default behavior on fresh installs uses Ollama Cloud, not a local-only endpoint that won't exist on iOS
- The 224-episode flood of failing localhost calls on startup is eliminated
- The 10-minute retry-cooldown loop against an unreachable localhost is no longer triggered on physical devices
- Voice conversation and agent chat automatically get the correct URL since they already pass the store

## Open Tail

- No explicit test coverage shown for the URL derivation logic or the fallback path
- The store-URL-to-base-URL stripping assumes the path suffix is /api/chat; other endpoint shapes may need handling

## Evidence

- transcript lines 1-22
- transcript lines 128-135
- transcript lines 248-270
- transcript lines 350-383
- transcript lines 514-521

