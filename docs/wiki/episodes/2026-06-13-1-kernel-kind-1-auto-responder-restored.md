---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - agent-note-responder
  - auto-responder
  - bounded-dedup-ring
supersedes:
  - 2026-06-13-2-bounded-dedup-ring-replaces-unbounded-hashset
  - 2026-06-13-1-agent-to-agent-responder-is-dead
related_claims: []
source_lines:
  - 7110-7147
  - 7189-7210
  - 7157-7167
captured_at: 2026-06-13T01:31:03Z
---

# Episode: Kernel kind:1 auto-responder restored as Rust module with bounded dedup

## Prior State

NostrAgentResponder.swift was deleted in PR #248, leaving no auto-response capability. The kernel had no inbound kind:1 note → LLM reply → publish path.

## Trigger

Cycle-8 Fable planner identified the auto-responder as dead/deleted needing restoration; Opus review of PR #421 found the dedup set was unbounded (unbounded HashSet re-serialized on every save — slow leak).

## Decision

Restored as kernel-owned Rust module (agent_note_responder.rs) with: off-actor spawn for D8 compliance (app_addr as usize across await boundary); bounded dedup ring (RespondedIds: VecDeque + HashSet, MAX_RESPONDED_IDS=4096, evict-oldest at cap); global/account-agnostic persistence (dedup by globally-unique event-id, fail-safe — can only suppress, never over-reply); responded_event_ids sidecar in snapshot for the conversations projection.

## Consequences

- Trusted inbound kind:1 notes now auto-generate LLM replies and publish them via handle_publish_agent_note
- OutboundTurnCache feeds the new podcast.social conversations projection (Item B dependency)
- Unbounded-set leak eliminated; ring survives save/reload and trims legacy unbounded files on load
- maxOutgoingTurnsPerRoot=10 + wtd-end gate cap each conversation thread

## Open Tail

- Tool loop / ask coordinator not in v1 scope — single reply per trusted inbound note

## Evidence

- transcript lines 7110-7147
- transcript lines 7189-7210
- transcript lines 7157-7167

