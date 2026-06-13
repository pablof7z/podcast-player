---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: product
status: active
subjects:
  - ai-inbox-triage
  - home-tab
  - featured-to-inbox
supersedes: []
related_claims: []
source_lines:
  - 84-88
  - 876-898
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Featured section replaced by AI Inbox with per-item rationale

## Prior State

Home tab had a 'Featured' section powered by AgentPicksService, showing agent-picked episodes without explicit reasoning.

## Trigger

User specified the Inbox should 'replace Featured tab with the same UX/UI' and 'each item the agent placed in the inbox to have a reason to be there' (line 84).

## Decision

The Featured section became Inbox. AgentPicksService was replaced by InboxTriageService. Each inbox episode displays the agent's one-line rationale. Section header renamed from 'Featured' to 'Inbox' / 'Inbox · <Category>'.

## Consequences

- AgentPicksService, its prompt, fallback, and streaming parser are now dead code (kept only for test references)
- HomeInboxBundle composes hero + 4 secondaries from persisted .inbox episodes, preferring agent-flagged hero over pubDate
- Every inbox card must show rationale — empty-rationale .inbox decisions are dropped at the store boundary

## Open Tail

- Dead AgentPicksService files still referenced by 3 test files — cleanup deferred

## Evidence

- transcript lines 84-88
- transcript lines 876-898

