---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - per-domain-projection-rev-bump
  - domain-revs-social
supersedes:
  - 2026-06-13-1-per-domain-projection-real-bump-doctrine
related_claims: []
source_lines:
  - 7537-7565
  - 7598-7628
  - 7738-7756
captured_at: 2026-06-13T02:14:15Z
---

# Episode: Per-domain projection rev bumps must use real production writers, not test-only fetch_add

## Prior State

Per-domain projection scaffolding could be written with mutation sites that bump only the global snapshot_signal, leaving domain_revs.{domain} frozen at 1. Tests masking this by manually fetch_add-ing the counter made the feature appear to work while being dead-on-arrival in production.

## Trigger

Opus review of PR #423 found domain_revs.social had zero production writers — both the inbound observer and outbound responder only called bare snapshot_signal.bump(), never advancing the social domain counter. This is the third recurrence of the same class (#399, #400, now #423).

## Decision

The canonical idiom is Infra::bump() (scoped to a Domain), which advances BOTH the domain-specific rev counter AND the global signal. All mutation sites must use the real observer path. Tests must NOT use fetch_add to mask this — they must drive real production observers and assert sidecar re-emission. For off-actor tasks that can't hold a full Infra, the two-step bump (domain counter fetch_add then signal.bump) must be mirrored explicitly. Recorded as a project-wide invariant in memory.

## Consequences

- Future domain projections must wire Infra::bump() at every mutation site before merge
- Real-path re-emit tests are now mandatory for new domain projections
- The social domain projection in #423 was fixed: inbound uses infra.bump() via scoped Infra, outbound mirrors the two-step explicitly
- Manual fetch_add in tests for the domain being tested is a red flag indicating dead-on-arrival scaffolding

## Open Tail

- Remaining domains (playback, downloads, identity, widget) still use manual fetch_add in tests — these are acceptable for existing domains where production bumps already exist, but any new domain must follow the Infra::bump() pattern

## Evidence

- transcript lines 7537-7565
- transcript lines 7598-7628
- transcript lines 7738-7756

