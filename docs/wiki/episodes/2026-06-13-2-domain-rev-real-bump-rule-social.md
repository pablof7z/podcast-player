---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: active
subjects:
  - domain-revs
  - social-projection
  - infra-bump
supersedes:
  - 2026-06-13-3-per-domain-rev-bump-must-use
related_claims: []
source_lines:
  - 7601-7628
captured_at: 2026-06-13T02:56:17Z
---

# Episode: Domain rev real-bump rule: social projection was dead-on-arrival

## Prior State

The podcast.social domain projection was deployed (PR #423) but domain_revs.social was never advanced by any production mutation site. Both the inbound and outbound paths called bare snapshot_signal.bump() (global-only), leaving the domain-specific counter frozen at 1.

## Trigger

Post-merge review found that mutation sites used Infra::bump() for other domains but the social observer's bump_social() and the outbound responder both called snapshot_signal.bump() directly, skipping domain_revs.social.

## Decision

Mirror the canonical Infra::bump() pattern: inbound observer gets a Domain::Social-scoped Infra calling infra.bump() (advances both domain_revs.social and global signal); outbound responder threads Arc<DomainRevs> and performs the two-step (counter fetch_add then signal.bump) that Infra::bump() performs internally. Test must drive the real observer path, not manual fetch_add.

## Consequences

- Standing architectural rule: per-domain rev bumps MUST use Infra::bump() (or its semantic equivalent) at real mutation sites — never bare snapshot_signal.bump() and never test-only fetch_add. Reviewers must grep for domain_revs writers and confirm the action path is among them.
- Two manual-fetch_add social tests replaced with three real-path tests driving the actual observer.
- iOS decode test added for snake_case podcast.social frame.

## Open Tail

*(none)*

## Evidence

- transcript lines 7601-7628

