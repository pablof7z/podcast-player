---
type: episode-card
date: 2026-06-03
session: 6706236b-c94a-4458-aa7b-6f71098aa55b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/6706236b-c94a-4458-aa7b-6f71098aa55b.jsonl
salience: architecture
status: active
subjects:
  - inbox-triage
  - agent-tools
  - inbox-llm
supersedes: []
related_claims: []
source_lines:
  - 1-52
  - 1923-2026
captured_at: 2026-06-12T13:04:25Z
---

# Episode: Inbox triage rewritten from background LLM pass to agent-based tool-call system

## Prior State

Inbox triage used a background pass that called Ollama locally (localhost:11434) for LLM classification, which produced cascading CompletionError failures when the local LLM was unavailable

## Trigger

User showed console output with 50+ consecutive `inbox_triage LLM triage failed` errors, demonstrating the background Ollama approach was fragile and produced no useful results

## Decision

Replaced background LLM pass with an agent-based implementation: `inbox_handler.rs` now uses `build_system_prompt_with_memory` from `agent_llm.rs`, sends all needy episodes in one agent message with `TRIAGE_TOOL_INSTRUCTIONS` and `TriageSink`, batch-writes priorities via `set_episode_priorities`, and uses `reconcile_pending` to stamp any episode the agent missed. `inbox_llm.rs` was gutted to just `TriageResult` + `TriageStatus` types with no LLM code. `stamp_pending` was replaced by `reconcile_pending`.

## Consequences

- Inbox triage no longer depends on a local Ollama instance being available
- Triage uses the same agent infrastructure as chat (shared system prompt builder, tool registry)
- Cold-start guard added for empty memory+history
- Batch episode handling replaces per-episode background calls
- Untriaged episodes fall back to recency-bucket heuristic via score() when agent cache has no entry

## Open Tail

- Whether the agent-based triage actually produces better priority scores than the old heuristic
- MAX_TRIAGE_TOOL_TURNS = 6 cap may need tuning

## Evidence

- transcript lines 1-52
- transcript lines 1923-2026

