---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - publish-episode
  - actor-stall
  - d8-nonblocking
  - self-enqueue
supersedes:
  - 2026-06-12-4-owned-podcast-backfill-synchronous-loop-per
related_claims: []
source_lines:
  - 3976-4048
  - 4102-4169
captured_at: 2026-06-12T13:02:10Z
---

# Episode: Owned-podcast backfill: synchronous N-upload actor stall caught and fixed via self-enqueue

## Prior State

Swift LiveAgentOwnedPodcastManager dispatched kernelPublishEpisode one per tick (yielding between episodes). Moving backfill into the kernel was correct D0 doctrine, but the initial Rust impl called publish_episode in a synchronous loop

## Trigger

Inline review discovered that dispatch_http blocks the actor thread (synchronous capability round-trip returning the result), confirmed by dispatch_http_async's own doc: 'Unlike dispatch_http, this does not block the actor thread'. An N-episode backfill would freeze all reactivity for minutes (D8 violation)

## Decision

Self-enqueue via nmp_app_dispatch_action: update_owned detects a private→public flip, collects episode IDs, then self-dispatches one {"op":"publish_episode"} per episode. nmp_app_dispatch_action only validates and enqueues an ActorCommand, returning immediately — each episode publishes in its own later actor tick with yield between

## Consequences

- D0 policy (kernel owns the backfill decision) preserved without D8 regression
- publish_episode reverted to private (reached via dispatch again)
- The self-enqueue pattern is a reusable D8-safe seam for any future batch operations on the actor thread
- Response carries episodes_queued (policy count) and episodes_accepted (FFI acceptance count)

## Open Tail

*(none)*

## Evidence

- transcript lines 3976-4048
- transcript lines 4102-4169

