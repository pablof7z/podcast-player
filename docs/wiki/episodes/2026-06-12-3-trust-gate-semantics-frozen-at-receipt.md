---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - trust-gate
  - agent-note-trusted
  - active-follow-set
supersedes: []
related_claims: []
source_lines:
  - 6479-6535
captured_at: 2026-06-12T22:28:01Z
---

# Episode: Trust gate semantics: frozen-at-receipt changed to live-at-projection evaluation

## Prior State

AgentNoteSummary.trusted was stamped at receipt time in agent_note_handler.rs (computed once from ActiveFollowSet.predicate at kind:1 arrival) and baked into the cache; the dedup check (if !cache.iter().any(|n| n.id == note.id)) prevented re-evaluation on redelivery, so a note arriving before its author was followed stayed trusted=false for the process lifetime

## Trigger

Opus review of PR #419 found the frozen-at-receipt semantics: following an author does not flip their existing notes to trusted, and the registration-ordering argument (ActiveFollowSet registered before AgentNotesObserver) only helps within a single delivery batch — not the common follow-after-note case

## Decision

Stop stamping trusted at receipt; compute trusted at projection time by applying ActiveFollowSet::predicate() to each note's author in the snapshot builder, making follow/unfollow immediately reflect on all existing notes and removing the registration-order dependency

## Consequences

- Follow/unfollow immediately reflects on all existing agent notes — the correct semantics for a trust gate feeding the agent-responder and conversations approval surface
- Registration order of observers no longer matters for trust correctness
- author_hex must be stored on AgentNoteSummary (currently only author_npub is stored) so the projection can feed the hex-based predicate
- The structural-only trust test (let _ = note.trusted) must be replaced with a behavioral test that follows an author and asserts their existing notes flip to trusted=true

## Open Tail

- #419 fix in progress — implementer reworking trust evaluation to projection-time and adding behavioral test
- Account-switch must also clear social_slot + agent_notes to prevent cross-account trust bleed

## Evidence

- transcript lines 6479-6535

