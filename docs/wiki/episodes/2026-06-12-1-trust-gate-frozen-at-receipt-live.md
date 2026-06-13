---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - trust-gate-semantics
  - social-projection
  - account-switch
supersedes:
  - 2026-06-12-1-social-graph-pull-reactive-push-with
related_claims: []
source_lines:
  - 6480-6525
  - 6620-6643
  - 6670-6683
captured_at: 2026-06-12T23:56:39Z
---

# Episode: Trust gate: frozen-at-receipt → live-at-projection

## Prior State

Agent note `trusted` was stamped at receipt time in `agent_note_handler.rs` and baked into the cache. A note arriving before the user followed its author stayed `trusted=false` forever — even after following. Additionally, `social_slot` and `agent_notes` (Session-scoped) were not cleared on account switch, so account A's follows and trust-stamped notes could leak into account B's session.

## Trigger

Opus review of PR #419 found the frozen-stamp semantics: dedup by id meant re-delivered notes never refresh the stamp, and the registration-ordering argument only covered kind:3-then-kind:1 in the same batch, not the common follow-after-note case.

## Decision

Stop stamping `trusted` at receipt. Cache `CachedAgentNote` with `author_hex` but no trust field. Compute `trusted` live at projection time in `agent_notes_snapshot()` by applying `ActiveFollowSet::predicate()` to each note's `author_hex` (fail-closed to false if no follow set). Clear `social_slot` and `agent_notes` on account switch via `clear_for_account_switch()`.

## Consequences

- Follow/unfollow immediately reflects on all existing notes — no stale trust
- Registration order of ActiveFollowSet vs AgentNotesObserver no longer matters
- CachedAgentNote stores author_hex instead of a baked trusted boolean
- Account A's state cannot bleed into account B's session after a switch
- Behavioral test added proving following flips an existing note's trusted status

## Open Tail

- The `author_hex` field on CachedAgentNote must be preserved; any future schema change must not lose the hex needed for the predicate

## Evidence

- transcript lines 6480-6525
- transcript lines 6620-6643
- transcript lines 6670-6683

