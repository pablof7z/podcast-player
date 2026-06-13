---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: product
status: active
subjects:
  - ai-inbox-triage
  - engagement-signal
  - inbox-visibility
supersedes: []
related_claims: []
source_lines:
  - 925-925
  - 1300-1360
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Agent engagement stats surfaced in Inbox UI subtitle

## Prior State

Per-show engagement signals (played/unplayed counts, recency) were computed and consumed by the LLM prompt, but never shown to the user. The Inbox section header was just 'Inbox' or 'Inbox · Category' with no indication of agent activity.

## Trigger

Codex review flagged that the spec called for agent work to be visible, but engagement was invisible (line 925). The original design described the Inbox as 'the daily editorial surface where the agent's intelligence becomes visible.'

## Decision

Added a quiet subtitle under the Inbox header: 'Triaged Nm ago · X picks across Y shows · Z archived'. Scopes by active category. Handles edge cases (single pick, single show, archived-only state, no timestamp yet).

## Consequences

- The agent's autonomous editorial work is now visible at a glance without opening any detail view
- VoiceOver reads the full subtitle for accessibility
- Counts narrow correctly when a category filter is active

## Open Tail

*(none)*

## Evidence

- transcript lines 925-925
- transcript lines 1300-1360

