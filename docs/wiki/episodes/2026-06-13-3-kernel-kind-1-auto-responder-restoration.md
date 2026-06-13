---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - agent-note-responder
  - kind1-auto-responder
  - responded-ids-ring
supersedes:
  - 2026-06-13-1-kernel-kind-1-auto-responder-restored
related_claims: []
source_lines:
  - 6906-6907
  - 7117-7147
  - 7157-7162
  - 7195-7210
captured_at: 2026-06-13T01:45:27Z
---

# Episode: Kernel kind:1 auto-responder restoration with bounded dedup

## Prior State

Swift NostrAgentResponder was deleted in PR #248, leaving no mechanism for the kernel to automatically respond to trusted inbound kind:1 Nostr notes. The BACKLOG noted the responder as 'DEAD/deleted-in-#248 needing RESTORATION.'

## Trigger

Cycle-8 Fable planner identified the auto-responder as a dead feature needing restoration. User mandated 'PROPER fixes — not added-on hacks — build on the most solid ground possible.'

## Decision

Implement Rust kernel-level responder (agent_note_responder.rs + sidecar agent_note_responder_cache.rs). Trusted inbound kind:1 → llm::complete_for_role reply → handle_publish_agent_note. v1 scope: reply + dedup + maxOutgoingTurnsPerRoot=10 + wtd-end gate, NO tool loop/ask coordinator. Off-actor spawn via runtime.spawn. Opus review then caught an unbounded HashSet for responded_event_ids — replaced with bounded RespondedIds ring (VecDeque + HashSet, MAX_RESPONDED_IDS=4096) that evicts oldest at capacity. Cache is global/account-agnostic (fail-safe: cross-account carryover can only suppress, never over-reply).

## Consequences

- Kernel now owns the auto-responder function — no Swift dependency for this path
- Unbounded dedup set replaced with bounded ring preventing slow memory leak
- Observer hook wired in register.rs with Domain::Social-scoped Infra for proper domain rev advancement
- Data_dir persistence for the responder cache with crash-safe atomic tmp-rename write

## Open Tail

*(none)*

## Evidence

- transcript lines 6906-6907
- transcript lines 7117-7147
- transcript lines 7157-7162
- transcript lines 7195-7210

