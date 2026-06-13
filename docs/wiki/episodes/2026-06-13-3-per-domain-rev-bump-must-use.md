---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-rev-bump-discipline
  - per-domain-projections
supersedes:
  - 2026-06-13-2-per-domain-projection-rev-bump-is
related_claims: []
source_lines:
  - 7536-7564
  - 7598-7628
  - 7646-7654
  - 7738-7755
captured_at: 2026-06-13T02:42:14Z
---

# Episode: Per-domain rev bump must use Infra::bump() — third recurrence of dormant-scaffolding bug class

## Prior State

Per-domain projections could be wired with bare snapshot_signal.bump() (global-only) for reactivity, with domain_revs advanced manually via fetch_add in tests

## Trigger

Opus review of #423 found domain_revs.social had zero production writers — the inbound observer and outbound responder both called snapshot_signal.bump() only, leaving domain_revs.social frozen at 1. The social sidecar would emit once then go silent forever, dead-on-arrival in production. Tests masked this by directly fetch_add-ing the counter

## Decision

Mutation sites must use Infra::bump() which advances both domain_revs.counter(Domain) AND global snapshot_signal in one call. Off-actor tasks must replicate Infra::bump's exact two-step (domain counter fetch_add then signal bump). Tests must drive real observer paths, never fetch_add-mask the counter

## Consequences

- This is the third recurrence of the same bug class (#399, #400, #423) — recorded as a durable architectural trap in project memory
- The idiom is now explicit: every working domain uses Domain::X-scoped Infra.bump(); SocialState.infra is already Domain::Social-scoped
- Manual fetch_add social tests replaced with real-path re-emit tests (social_inbound_note_reemits_on_each_new_note_real_path)

## Open Tail

- Future domain projections must be audited for real production bump-wiring before merge, not just test-path bump verification

## Evidence

- transcript lines 7536-7564
- transcript lines 7598-7628
- transcript lines 7646-7654
- transcript lines 7738-7755

