---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-revs
  - projection-real-bump
  - per-domain-sidecar
supersedes:
  - 2026-06-13-1-per-domain-projection-rev-bumps-must
related_claims: []
source_lines:
  - 7536-7558
  - 7559-7578
  - 7600-7627
captured_at: 2026-06-13T02:30:19Z
---

# Episode: Per-domain projection rev-bump is a recurring dead-on-arrival trap

## Prior State

New per-domain projection scaffolding registers a rev counter and is expected to push updates when the domain mutates.

## Trigger

Third occurrence (#399, #400, now #423) where a per-domain rev counter (domain_revs.social) was only bumped in tests (via manual fetch_add), never by the production observer/responder — the sidecar emitted once then idled forever, invisible to users.

## Decision

Per-domain projection rev bumps MUST use Infra::bump() or equivalent at real mutation sites; every new domain projection MUST have a real-path re-emit test that drives the production observer (NOT a manual fetch_add). Recorded as a durable architectural invariant in project memory.

## Consequences

- Domain::Social fixed: inbound observer uses social_infra.bump() (advances both domain_revs.social and global signal), outbound responder mirrors the two-step Infra::bump() pattern manually since it runs off-actor
- Three real-path tests added (social_inbound_note_reemits_on_each_new_note_real_path, social_empty_emits_tombstone_then_idles, social_inbound_note_excludes_library_and_playback_sidecars) that explicitly guard against fetch_add masking
- Infra::bump() is now the canonical idiom for all domain-scoped mutations

## Open Tail

*(none)*

## Evidence

- transcript lines 7536-7558
- transcript lines 7559-7578
- transcript lines 7600-7627

