---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: reversal
status: active
subjects:
  - ai-inbox-triage
  - inbox-model
  - agent-autonomy
supersedes: []
related_claims: []
source_lines:
  - 39-47
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Inbox model resolved: autonomous agent, no review surface

## Prior State

An open design question existed: Castro-style (agent proposes, user decides) vs. agent-decides-by-default with a review mode. The spec noted 'Very different UIs — needs a commit before designing the home tab.'

## Trigger

User explicitly chose 'agent-decides, no review, full autonomy' (line 47) when presented with the unresolved question.

## Decision

The agent triages autonomously with no review mode. Episodes are routed to Inbox or Archive without user confirmation. No review UI will be built.

## Consequences

- No review-mode UI needed — eliminates an entire surface from the design
- Every routing decision carries a one-line rationale (the only transparency mechanism)
- Recovery path is limited to: finding archived episodes on the show page, or playing them to auto-unarchive
- Mistakes are permanent unless the user manually intervenes (no TTL or reconsideration in v1)

## Open Tail

- A reconsideration/TTL mechanism may be needed if user feedback shows the agent archives too aggressively

## Evidence

- transcript lines 39-47

