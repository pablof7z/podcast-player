---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - agent-note-responder-cache
  - dedup
  - responded-ids
supersedes: []
related_claims: []
source_lines:
  - 7157-7162
  - 7189-7221
captured_at: 2026-06-13T00:28:47Z
---

# Episode: Bounded dedup ring replaces unbounded HashSet in responded_event_ids

## Prior State

The initial #421 implementation used an unbounded HashSet<String> for responded_event_ids — re-serialized in full on every save, with no eviction. A slow leak that would grow without bound.

## Trigger

Opus review flagged SHOULD-FIX-1: unbounded set is a slow leak, re-serialized in full on every save, inconsistent with the session's 'durable proper architecture, no deferred hacks' mandate.

## Decision

Replace with a bounded RespondedIds ring: VecDeque<String> (insertion order) + HashSet<String> (O(1) membership), capped at MAX_RESPONDED_IDS=4096. insert() evicts oldest from both structures on overflow; duplicate insert is a no-op (no reorder, no growth). Persistence serializes the VecDeque and re-applies cap on load. Cache is global/account-agnostic — cross-account carryover can only suppress (fail-safe), never over-reply.

## Consequences

- No unbounded memory growth from the dedup set
- Persistence handles previously-unbounded files by trimming on load
- Cross-account identity switches don't clear the dedup set (unlike account-scoped social state) — by design, since dedup by globally-unique event-id is fail-safe
- 3 new tests: ring eviction at cap, duplicate insert no-op, save-reload order preservation

## Open Tail

*(none)*

## Evidence

- transcript lines 7157-7162
- transcript lines 7189-7221

