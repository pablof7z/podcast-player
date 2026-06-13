---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - relay-config-persistence
  - backlog-truthfulness
  - data-dir
supersedes: []
related_claims: []
source_lines:
  - 6761-6822
  - 6796-6802
captured_at: 2026-06-13T00:16:40Z
---

# Episode: Relay-config persistence: planned work found already shipped

## Prior State

BACKLOG entry `relay-config-c-abi-persistence` was listed as OPEN/upcoming work. A large comment block in `register.rs:233-262` stated 'no relay persistence on the C-ABI path' and 'intentionally still unconditional.' The cycle-8 bench included relay-config persistence as a candidate.

## Trigger

Cycle-8 planner verified against origin/main and found commit `0dcf9680` (PR #220) already shipped the full persistence loop: load path in `ffi/data_dir.rs:112`, save path in `host_op_handler/settings_actions.rs:391` → `ffi/relay_persist.rs`. The BACKLOG and source comments directly contradicted the code two files away.

## Decision

Drop relay-config persistence from cycle-8 bench entirely. Mark BACKLOG entry as DONE (citing `0dcf9680`). Rewrite the stale `register.rs` comment block to reflect that persistence now exists, explaining that the unconditional seed remains for a structural reason (slot is empty at register time; actor reads initial_relays only when handling Start, which fires after register returns).

## Consequences

- Frees a work lane in cycle-8 (was rated S-M effort)
- Three doc/comment sites corrected for truthfulness: BACKLOG entry, register.rs comment block, and the agent-to-agent BACKLOG entry (stale reference to Swift responder)
- Seed behavior is now documented as intentional rather than missing

## Open Tail

*(none)*

## Evidence

- transcript lines 6761-6822
- transcript lines 6796-6802

