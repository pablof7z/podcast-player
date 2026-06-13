---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: product
status: active
subjects:
  - token-usage
  - agent-run-log
  - telemetry-honesty
supersedes: []
related_claims: []
source_lines:
  - 1065-1108
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Token usage must be honest, not zero-filled

## Prior State

AgentAPIResponse.tokensUsed was a required AgentTokenUsage field; providers that omitted usage data resulted in 0→0 being displayed in the run log UI and recorded in telemetry.

## Trigger

Audit found zeroed token usage fallback in AgentChatSession+Turns.swift:313 — silent telemetry loss.

## Decision

Made tokensUsed optional (AgentTokenUsage?). Synthesized Codable gives backward-compat for free. Run log UI shows '—' instead of '0→0' for unreported turns. Debug log names the model when usage is nil.

## Consequences

- Run log UI no longer shows misleading zero tokens for providers that don't report usage
- Old logs with populated fields still decode correctly
- AgentRunCollector already guarded with if let — no change needed there

## Open Tail

*(none)*

## Evidence

- transcript lines 1065-1108

