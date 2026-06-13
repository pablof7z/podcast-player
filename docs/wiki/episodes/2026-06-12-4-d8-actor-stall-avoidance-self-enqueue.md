---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - d8-actor-stall
  - self-enqueue
  - owned-podcast-backfill
supersedes: []
related_claims: []
source_lines:
  - 3996-4048
  - 4105-4131
captured_at: 2026-06-12T13:47:03Z
---

# Episode: D8 actor-stall avoidance: self-enqueue for multi-item kernel backfill

## Prior State

The Swift loop dispatched one kernelPublishEpisode per tick, yielding between episodes — the actor stayed responsive during multi-episode backfill.

## Trigger

Moving backfill into update_owned naively created a synchronous for-loop calling publish_episode N times — each call blocks the actor thread on Blossom upload + sign + broadcast (dispatch_http is synchronous). A 100-episode catalog flip would stall all reactivity for minutes.

## Decision

Use nmp_app_dispatch_action to self-enqueue one {'op':'publish_episode'} per episode. Each dispatch validates + enqueues an ActorCommand and returns immediately — each episode publishes in its own later tick with the actor yielding between.

## Consequences

- D0 policy (kernel owns backfill) is preserved without a D8 responsiveness regression
- The publish_episode action already existed as a real route in the namespace router
- Self-enqueue is the established non-blocking pattern (used by run_now and nmp_dispatch) — not a new async mechanism

## Open Tail

*(none)*

## Evidence

- transcript lines 3996-4048
- transcript lines 4105-4131

