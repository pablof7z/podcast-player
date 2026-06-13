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
  - self-dispatch
  - d8-invariant
supersedes: []
related_claims: []
source_lines:
  - 4048-4048
  - 4097-4099
  - 4107-4134
captured_at: 2026-06-12T14:08:15Z
---

# Episode: D8 actor-stall in owned-podcast backfill → self-enqueue seam

## Prior State

PR #397's initial implementation used a synchronous for-loop calling publish_episode for each episode in a private→public flip (mirroring the old Swift one-per-tick dispatch pattern but running all N episodes in a single actor tick).

## Trigger

Inline review found that dispatch_http blocks the actor thread (returns synchronous HTTP result via dispatch_capability). A 100-episode catalog flip would freeze all reactivity for minutes — a D8 regression vs. the old Swift loop which yielded between episodes.

## Decision

Replace the synchronous loop with self-enqueue: update_owned collects episode IDs under the store lock, drops the lock, then self-dispatches N {"op":"publish_episode"} actions via nmp_app_dispatch_action (which only validates + enqueues an ActorCommand and returns immediately). Each episode publishes in its own later actor tick.

## Consequences

- D0 policy (kernel decides what to publish) stays in the kernel
- D8 responsiveness preserved — actor yields between episodes
- publish_episode reverted to private (reached via dispatch again)
- Response carries episodes_queued (policy) and episodes_accepted (FFI)

## Open Tail

*(none)*

## Evidence

- transcript lines 4048-4048
- transcript lines 4097-4099
- transcript lines 4107-4134

