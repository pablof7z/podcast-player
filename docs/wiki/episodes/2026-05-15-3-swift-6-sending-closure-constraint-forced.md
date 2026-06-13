---
type: episode-card
date: 2026-05-15
session: d0447a6c-e8a4-4913-a5bd-cd462c96487a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0447a6c-e8a4-4913-a5bd-cd462c96487a.jsonl
salience: root-cause
status: active
subjects:
  - swift6-concurrency
  - taskgroup-sending
  - episode-publishing
supersedes: []
related_claims: []
source_lines:
  - 1324-1332
  - 1377-1379
captured_at: 2026-06-12T12:33:39Z
---

# Episode: Swift 6 sending-closure constraint forced serial over concurrent episode publishing

## Prior State

Retroactive episode publishing was initially implemented using withTaskGroup for concurrent publishing of all episodes.

## Trigger

Build error: 'passing closure as a sending parameter risks causing data races between code in the current task and concurrent execution of the closure' — Swift 6 strict concurrency rejects passing self across task group boundaries.

## Decision

Replaced withTaskGroup with a sequential for loop. Marked pure helper methods as nonisolated. Justified by retroactive publishing being a rare one-shot operation where serial performance is acceptable.

## Consequences

- Episode publishing during visibility flip is serial, not parallel
- Sets a pattern: avoid withTaskGroup when self (actor-isolated) must cross the closure boundary in Swift 6
- nonisolated marking applied to VTT/chapters helpers as they don't access instance state

## Open Tail

*(none)*

## Evidence

- transcript lines 1324-1332
- transcript lines 1377-1379

