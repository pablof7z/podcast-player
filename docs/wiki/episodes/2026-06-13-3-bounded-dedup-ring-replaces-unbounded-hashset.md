---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: active
subjects:
  - responder-cache-bounding
  - agent-note-responder
supersedes:
  - 2026-06-13-3-kernel-kind-1-auto-responder-restoration
related_claims: []
source_lines:
  - 7196-7209
captured_at: 2026-06-13T02:14:15Z
---

# Episode: Bounded dedup ring replaces unbounded HashSet for responded_event_ids

## Prior State

ResponderCache.responded_event_ids was an unbounded HashSet<String>, re-serialized in full on every save — a slow memory leak that grows without bound as the responder processes more events.

## Trigger

Opus review of PR #421 flagged SHOULD-FIX-1: unbounded HashSet re-serialized in full on every save. Consistent with the project's 'durable proper architecture, no deferred hacks' constraint.

## Decision

Replaced unbounded HashSet with RespondedIds ring: VecDeque<String> for insertion order + HashSet<String> for O(1) membership. Cap is MAX_RESPONDED_IDS = 4096. insert() evicts the oldest from both structures on overflow; duplicate insert is a no-op (no growth, no reorder). Persistence serializes the ordered VecDeque (oldest-first); from_ordered_vec re-applies cap on load. Public API unchanged (record_response / already_responded / turns_for_root).

## Consequences

- Unbounded growth eliminated — responder cache caps at 4096 entries
- Genuine re-delivery never displaces a distinct recent id (duplicate is no-op)
- Previously-unbounded persisted files are trimmed on next load
- outbound_turns left unbounded by design (keyed by active roots)

## Open Tail

*(none)*

## Evidence

- transcript lines 7196-7209

