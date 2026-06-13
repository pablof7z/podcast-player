---
type: episode-card
date: 2026-06-03
session: 55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1.jsonl
salience: root-cause
status: active
subjects:
  - player-queue
  - up-next
  - playback-queue
supersedes: []
related_claims: []
source_lines:
  - 935-967
captured_at: 2026-06-12T13:11:23Z
---

# Episode: Up Next queue read/write split bug

## Prior State

The ios/Podcast app's Up Next sheet was presumed working — swipe-to-enqueue, clear, and play-next appeared functional because they dispatched without error.

## Trigger

Agent investigating queue unification discovered that Up Next renders from PlaybackQueue (the canonical Rust projection via resolve_queue_rows) but the four player queue ops (enqueue, dequeue, clear_queue, play_next) mutated a separate PlayerActor.queue that nothing rendered.

## Decision

Routed all four queue ops through the canonical PlaybackQueue instead of deleting them. Dropped the vestigial PlayerActor.queue field and its methods.

## Consequences

- Up Next swipe, clear, and play-next now operate on the queue the user actually sees
- PlayerActor no longer maintains a shadow queue that can silently diverge from the UI
- Nine new routing tests pin the canonical append, rejection, dequeue, clear, and play-next paths

## Open Tail

*(none)*

## Evidence

- transcript lines 935-967

