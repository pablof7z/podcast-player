---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: architecture
status: active
subjects:
  - ai-inbox-triage
  - rationale-invariant
  - data-integrity
supersedes: []
related_claims: []
source_lines:
  - 928-929
  - 1099-1113
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Empty-rationale invariant enforced at store boundary

## Prior State

The LLM code path dropped empty-rationale inbox decisions, but the store boundary (applyTriageDecisions) accepted .inbox with nil or blank rationale. Any future bypass of runLLM would create chip-less inbox cards.

## Trigger

Codex review flagged the invariant as fragile — only enforced on one code path (line 928).

## Decision

applyTriageDecisions now filters .inbox patches whose rationale is nil or whitespace-only, dropping them entirely rather than persisting. The doc comment records the invariant.

## Consequences

- The store layer is the single enforcement point — adding new triage producers requires only that they go through applyTriageDecisions
- Invalid .inbox patches are silently skipped (no logging), matching the existing pattern for no-op writes

## Open Tail

*(none)*

## Evidence

- transcript lines 928-929
- transcript lines 1099-1113

