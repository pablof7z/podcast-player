---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - domain-revs
  - per-domain-projection
  - dormant-scaffolding
supersedes: []
related_claims: []
source_lines:
  - 7537-7566
captured_at: 2026-06-13T01:31:03Z
---

# Episode: Per-domain projection real-bump dormancy as recurring architectural trap

## Prior State

Per-domain typed projections (DomainRevs with per-domain bump) were being added as scaffolding, with bump_domain calls only in test code — production push path never advanced the domain rev, so sidecars emitted once then went silent forever.

## Trigger

Opus review of PR #423 found domain_revs.social has zero production writers — both the inbound observer and outbound responder bump only the global snapshot_signal, never the social domain rev. This is the third independent occurrence of the same class of bug (#399, #400, #423).

## Decision

Recorded as architectural trap in project memory (per_domain_projection_real_bump.md). Rule: every new per-domain projection must wire bump_domain at real mutation sites in the observer/responder, verified by a real-path (non-test) re-emit test that does not fetch_add the counter directly. Tests that manually bump domain_revs mask the bug and must not be the only verification.

## Consequences

- All three prior occurrences (#399, #400, #423) shared the same structural cause: scaffolding that passes tests but is dead-on-arrival in production
- Future per-domain projections must include a real-path bump wiring proof before merge
- PR #423 fix in progress: adding Domain::Social bump at both inbound observer and outbound responder mutation sites

## Open Tail

*(none)*

## Evidence

- transcript lines 7537-7566

