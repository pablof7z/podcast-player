---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: active
subjects:
  - domain-rev-safety
  - pull-path-invariant
supersedes: []
related_claims: []
source_lines:
  - 4237-4254
captured_at: 2026-06-12T13:47:03Z
---

# Episode: Global rev must always be bumped alongside domain revs (pull-path invariant)

## Prior State

Per-domain revs were added to enable per-domain delta frames — a naive implementation might only bump the domain-specific counter for a mutation.

## Trigger

Review of PR #400's bump_domain wiring: if any mutation site bumps only its domain rev without advancing the global rev, the pull path (nmp_app_podcast_snapshot, gated on global rev) would miss that update and show stale UI.

## Decision

Infra::bump always advances both the domain counter and the global rev. The docs explicitly enforce this. Proof tests confirm: real_queue_mutation_bumps_only_playback_domain advances only playback domain rev, but the global rev is also bumped.

## Consequences

- The existing pull path is completely unaffected — golden byte-identical, no shell behavior change
- Even a hypothetical wrong domain tag is caught by the global-rev fallback
- The domain tagging is forward-compatible infra: dormant-by-design until shells consume per-domain frames

## Open Tail

*(none)*

## Evidence

- transcript lines 4237-4254

