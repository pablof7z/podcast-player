---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - per-domain-projection-real-bump
  - domain-revs-bump
supersedes:
  - 2026-06-13-4-per-domain-projection-real-bump-dormancy
related_claims: []
source_lines:
  - 7546-7564
  - 7566-7577
  - 7599-7627
captured_at: 2026-06-13T01:45:27Z
---

# Episode: Per-domain projection real-bump doctrine (3x recurring trap)

## Prior State

Per-domain delta sidecars could be created with DomainRevs counters, but production mutation sites only called snapshot_signal.bump() (global-only), leaving the domain-specific rev frozen at 1. Tests masked this by manually fetch_add-ing the counter, making the sidecar appear to work in tests while being dead-on-arrival in production.

## Trigger

Opus review of #423 found domain_revs.social had zero production writers — both mutation sites bumped only the global signal. This is the same dormant-scaffolding class that shipped broken in #399 and #400 (third recurrence).

## Decision

All per-domain projection mutation sites MUST use Infra::bump() (which advances both domain_revs.counter(Domain::X) AND the global snapshot_signal). Tests MUST NOT mask dormant scaffolding with manual counter bumps — they must drive the real observer path. Pattern codified in memory file per_domain_projection_real_bump.md.

## Consequences

- #423 fix replaced snapshot_signal.bump() calls with infra.bump() at both inbound and outbound mutation sites
- Manual fetch_add tests replaced with real-path observer re-emit tests that assert the second note re-emits podcast.social
- Future domain sidecar implementations must wire Infra::bump() at design time — the memory file catches this before code review

## Open Tail

*(none)*

## Evidence

- transcript lines 7546-7564
- transcript lines 7566-7577
- transcript lines 7599-7627

