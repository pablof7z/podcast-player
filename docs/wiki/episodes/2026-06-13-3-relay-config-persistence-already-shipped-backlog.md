---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: active
subjects:
  - relay-config
  - backlog-truthfulness
  - source-of-truth
supersedes:
  - 2026-06-13-3-relay-config-persistence-planned-work-found
related_claims: []
source_lines:
  - 6764-6766
  - 6977-6983
captured_at: 2026-06-13T00:28:47Z
---

# Episode: Relay-config persistence already shipped — BACKLOG and comments were stale

## Prior State

BACKLOG listed relay-config-c-abi-persistence as OPEN. register.rs:233-262 had a large comment block stating 'no relay persistence on the C-ABI path' and that the initial seed was unconditional by design. The agent-to-agent BACKLOG entry said the responder 'still lives on Swift NostrAgentResponder path.'

## Trigger

Cycle-8 Fable planner audit found commit 0dcf9680 already shipped the full implementation: load path in ffi/data_dir.rs:112 (sidecar .nmp-relay-config.json → set_initial_relays_for_start), save path in host_op_handler/settings_actions.rs:391 → ffi/relay_persist.rs.

## Decision

Drop relay-config from cycle-8 scope. Mark BACKLOG entry as DONE (citing 0dcf9680). Rewrite the stale register.rs comment block to reflect that persistence now exists (seed is unconditional because slot is empty at register time, but persisted edits override on subsequent launches). Correct the agent-to-agent entry to say Swift responder was deleted in #248.

## Consequences

- Prevented redundant reimplementation of already-shipped functionality
- Three doc/comment sites now match code reality (BACKLOG relay-config, BACKLOG agent-to-agent, register.rs comment block)
- Cycle-8 scope correctly excluded relay-config, making room for the genuine unshipped items

## Open Tail

*(none)*

## Evidence

- transcript lines 6764-6766
- transcript lines 6977-6983

