---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - social-graph
  - trust-gate
  - follow-list-projection
  - active-follow-set
supersedes:
  - 2026-06-12-2-social-graph-one-shot-pull-fetch
  - 2026-06-12-3-trust-gate-semantics-frozen-at-receipt
related_claims: []
source_lines:
  - 6061-6087
  - 6291-6363
  - 6479-6526
  - 6620-6647
  - 6669-6683
captured_at: 2026-06-12T22:54:33Z
---

# Episode: Social graph: pull → reactive push with live-at-projection trust gate

## Prior State

Social graph used an 8s-timeout hardcoded-relay pull path (fetch_relay_events_async + subscribe_until_eose). Trust was stamped at note-receipt time and frozen — a note arriving before its author was followed stayed trusted=false forever. Social slot and agent notes were not cleared on account switch, causing cross-account state bleed.

## Trigger

NMP v0.6.0 shipped nmp-nip02 (FollowListProjection + ActiveFollowSet). Opus review then caught two bugs: (1) frozen-at-receipt trust semantics are wrong for a gate feeding the agent-responder/approval surface, and (2) social_slot + agent_notes leak across account switches.

## Decision

Replace the 8s pull path entirely with reactive FollowListProjection (rides the standing account_profile_interest subscription, no separate relay connection). Compute trusted live at projection time from ActiveFollowSet.predicate() applied to each note's author_hex, not at receipt. Clear social_slot and agent_notes on account switch via clear_for_account_switch. Delete the now-orphaned relay.rs module.

## Consequences

- Follow/unfollow immediately flips trusted on all existing notes; no registration-order dependency
- ActiveFollowSet Arc injected into SocialState via with_follow_set — fail-closed to trusted=false without it (D6)
- No cross-account state bleed after identity change
- handle_fetch_contacts returns {"ok":true,"status":"refreshed"} — no relay connection, pure trigger
- relay.rs deleted (only app-side caller was the old pull path)
- Behavioral test proves: cache note from X (trusted=false) → follow X via kind:3 → same note projects trusted=true

## Open Tail

- Conversations projection (group agent_notes by root_event_id) — now unblocked by correct trust gate
- Agent-to-agent kind:1 responder — same unblock
- kernelsigner-dead-code-removal — KernelSigner has zero callers but removal cascades into NostrSigner protocol conformers

## Evidence

- transcript lines 6061-6087
- transcript lines 6291-6363
- transcript lines 6479-6526
- transcript lines 6620-6647
- transcript lines 6669-6683

