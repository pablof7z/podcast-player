---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: active
subjects:
  - trust-gate
  - agent-notes
  - social-state
  - active-follow-set
supersedes:
  - 2026-06-12-1-trust-gate-frozen-at-receipt-live
related_claims: []
source_lines:
  - 6529-6531
  - 6625-6635
  - 6637-6639
captured_at: 2026-06-13T00:16:40Z
---

# Episode: Trust gate: frozen-at-receipt → live-at-projection

## Prior State

Agent note `trusted` was stamped at receipt time in `AgentNotesObserver::on_kernel_event`. A note arriving before its author was followed would stay `trusted=false` forever — even after following them. The follow-set was not consulted at projection time.

## Trigger

Opus review of #419 caught the correctness bug: trust must be live-computed from the follow set, not frozen at receipt. Also found: account-switch did not clear social/agent-notes state (cross-account leak), and no behavioral test existed for follow-flips-trust.

## Decision

`trusted` is now computed live at projection time: `agent_notes_snapshot` builds a predicate from the live `ActiveFollowSet` Arc, applies it to each `CachedAgentNote.author_hex`, and defaults to `false` when no follow set exists (fail-closed, D6). `clear_for_account_switch()` zeroes `social_slot` and `agent_notes` on identity change. Behavioral test `existing_note_becomes_trusted_after_following_author` added.

## Consequences

- Following/unfollowing an author immediately flips trust on all their existing notes — no stale trust verdicts
- Account switch now fully resets social state — no cross-account note/follow leakage
- The trust gate is now correct and live, which is the prerequisite foundation for the agent-to-agent kind:1 responder
- CachedAgentNote carries author_hex but no trust field — the wire DTO AgentNoteSummary is unchanged

## Open Tail

*(none)*

## Evidence

- transcript lines 6529-6531
- transcript lines 6625-6635
- transcript lines 6637-6639

