---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - agent-responder
  - nostr-autopilot
  - trust-gate
supersedes:
  - 2026-06-13-2-agent-responder-dead-swift-path-kernel
related_claims: []
source_lines:
  - 6762-6819
  - 7114-7145
captured_at: 2026-06-13T00:28:47Z
---

# Episode: Agent-to-agent responder is dead code — restore as kernel implementation, not Swift migration

## Prior State

The BACKLOG and code comments described the agent-to-agent kind:1 responder as still living on a Swift NostrAgentResponder compat path that needed migration to the kernel. The #419 trust gate was understood to feed into existing functionality.

## Trigger

Cycle-8 Fable planner audit discovered that NostrAgentResponder.swift (+Delegation.swift) was deleted in PR #248; AgentRelayBridge has zero constructor call sites; recordNostrTurn has zero callers; the kernel agentNotes projection is decoded but consumed nowhere — the trust gate from #419 ships into a void.

## Decision

Reframe Item A as feature restoration (not refactoring/migration): build a new Rust kernel `agent_note_responder` module. v1 scope deliberately excludes tool loop and ask coordinator: plain `complete_for_role` reply + dedup + maxOutgoingTurnsPerRoot=10 + wtd-end gate. Off-actor spawn via `runtime.spawn` for D8 compliance.

## Consequences

- The #419 trust gate now has a live consumer — inbound trusted notes flow to the responder
- Works on Android/TUI for free (kernel-owned, no Swift dependency)
- Item B (conversations projection) is unblocked and will show responder replies as outgoing turns
- Blossom audio-path migration stays blocked upstream (no NMP API for per-podcast NIP-F4 key roster registration)

## Open Tail

- v2 scope: 20-turn tool loop and owner-consult ask coordinator (deferred from Swift-era impl)
- social-publish-relay-target: kernel social publishing still hardcodes relay.primal.net

## Evidence

- transcript lines 6762-6819
- transcript lines 7114-7145

