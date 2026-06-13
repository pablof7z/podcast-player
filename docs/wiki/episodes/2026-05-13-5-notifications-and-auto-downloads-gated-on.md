---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: architecture
status: active
subjects:
  - ai-inbox-triage
  - refresh-pipeline
  - notification-gating
supersedes: []
related_claims: []
source_lines:
  - 921-922
  - 1494-1563
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Notifications and auto-downloads gated on triage completion

## Prior State

SubscriptionRefreshService fired notifications and auto-downloads immediately during the upsert sweep, before any triage verdict existed. A soon-to-be-archived episode would already have pushed a notification and queued a download.

## Trigger

Codex review identified that side effects fired before triage, violating the 'silently archived' contract (line 921-922).

## Decision

Refactored refresh pipeline: collect PendingSideEffects during the sweep, run triage, poll InboxTriageService.isRunning until false (60s deadline), then dispatch only for episodes that survived the archive filter.

## Consequences

- Pull-to-refresh has up to 60s latency if the LLM is slow — acceptable trade-off for correctness
- Untriaged episodes (no API key, candidate cap exceeded) still get notifications and downloads as before — only explicit .archived verdicts are suppressed
- The single-podcast refresh path also gates side effects for consistency
- New side-effect types must be added to dispatchSideEffects with the same archive filter

## Open Tail

- The 60s deadline constant could be lifted to Configuration for tuning

## Evidence

- transcript lines 921-922
- transcript lines 1494-1563

