---
type: episode-card
date: 2026-06-09
session: 0964cb48-04df-4b35-9ad9-67cdc6a9d488
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0964cb48-04df-4b35-9ad9-67cdc6a9d488.jsonl
salience: reversal
status: active
subjects:
  - android-library
  - android-parity-docs
supersedes: []
related_claims: []
source_lines:
  - 4517-4537
captured_at: 2026-06-12T13:38:33Z
---

# Episode: Library/subscribe reclassified from stub to shipped — docs were stale

## Prior State

Documentation (android-parity.md) described Library/subscribe as 'M2.A stub' — subscribed shows were believed to not land in the library.

## Trigger

On-device testing showed library=1 subs=1 after subscribe, Library grid rendered the show with artwork, and the subscription persisted across app restart.

## Decision

Corrected the parity doc: Library/subscribe is Shipped, not a stub. The build_library_snapshot via all_podcasts() was already surfacing subscribed shows correctly.

## Consequences

- Library/subscribe removed from the to-build backlog
- Stale M2.A stub narrative replaced with verified Shipped status

## Open Tail

*(none)*

## Evidence

- transcript lines 4517-4537

