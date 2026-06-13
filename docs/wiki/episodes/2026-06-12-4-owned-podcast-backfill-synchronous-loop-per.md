---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - owned-podcast-backfill
  - d8-actor-stall
  - self-dispatch
supersedes:
  - 2026-06-12-4-d8-actor-stall-avoidance-self-enqueue
related_claims: []
source_lines:
  - 3976-3997
  - 4014-4048
  - 4102-4148
captured_at: 2026-06-12T12:24:35Z
---

# Episode: Owned-podcast backfill: synchronous loop → per-episode self-enqueue (D8 regression caught in review)

## Prior State

The Swift side looped kernelPublishEpisode one-per-tick from LiveAgentOwnedPodcastManager, yielding between episodes — responsive but policy lived in the wrong layer (shell, not kernel D0)

## Trigger

Inline review of PR #397 found that moving the backfill into update_owned as a synchronous N-episode loop would block the actor thread for the entire backfill (dispatch_http blocks per Blossom upload) — a 50–100 episode catalog flip would freeze all reactivity for minutes

## Decision

Self-enqueue per-episode publish_episode actions via nmp_app_dispatch_action (validates + enqueues ActorCommand, returns immediately). Each episode publishes in its own later actor tick with the actor yielding between them. D0 policy stays in kernel, D8 responsiveness preserved

## Consequences

- Private→public flip is now one atomic kernel op (visibility + show republish + N self-enqueued episode publishes)
- publish_episode reverted to private fn since it's reached via dispatch again
- Test adapted to assert enqueue contract (episodes_queued count)
- Swift LiveAgentOwnedPodcastManager loop deleted — shell just triggers update_owned

## Open Tail

*(none)*

## Evidence

- transcript lines 3976-3997
- transcript lines 4014-4048
- transcript lines 4102-4148

