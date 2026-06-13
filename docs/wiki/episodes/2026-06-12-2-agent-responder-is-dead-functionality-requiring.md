---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - agent-responder
  - nostr-conversations
supersedes: []
related_claims: []
source_lines:
  - 6762-6781
  - 6816-6823
captured_at: 2026-06-12T23:56:39Z
---

# Episode: Agent-responder is dead functionality requiring kernel restoration

## Prior State

The BACKLOG listed the agent-to-agent responder as 'OPEN — LLM responder loop still lives on the Swift NostrAgentResponder path,' implying it was a migration task from Swift to Rust.

## Trigger

Fable planner audit discovered that `NostrAgentResponder.swift` (+Delegation) was deleted in PR #248, `AgentRelayBridge` has zero constructor call sites, `recordNostrTurn` has zero callers, and `state.nostrConversations` is never populated — #419's trust gate ships into a void with no consumer.

## Decision

The responder must be RESTORED as new kernel functionality, not migrated. Scope v1: `complete_for_role` reply + dedup via responded-ids sidecar + maxOutgoingTurnsPerRoot=10 + wtd-end gate. No tool loop or ask coordinator in v1.

## Consequences

- Item A is feature restoration, not refactoring — new `agent_note_responder.rs` module needed
- #419's trust gate now has a consumer — the responder checks AgentNoteSummary.trusted before replying
- Item B (conversations projection) deferred until A merges — both touch agent_note_handler.rs; boundary rule: A owns responder+observer hook, B owns publish-capture+snapshots
- The historical Swift reference implementation (466 lines at commit 0c590b26^) serves as spec, not codebase

## Open Tail

- Tool loop and ask coordinator are v2 — deferred, not abandoned
- Conversations projection (Item B) will make responder turns visible in the UI

## Evidence

- transcript lines 6762-6781
- transcript lines 6816-6823

