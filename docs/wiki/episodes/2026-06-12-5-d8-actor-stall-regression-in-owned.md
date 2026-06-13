---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: active
subjects:
  - actor-model
  - d8-invariant
  - publish-lifecycle
  - blossom-upload
supersedes:
  - 2026-06-12-4-owned-podcast-backfill-synchronous-n-upload
related_claims: []
source_lines:
  - 3976-4048
  - 4107-4131
captured_at: 2026-06-12T13:58:37Z
---

# Episode: D8 actor-stall regression in owned-podcast backfill caught in review

## Prior State

Owned-podcast private→public flip backfill was implemented as a synchronous loop calling `publish_episode` N times within a single `update_owned` dispatch

## Trigger

Inline review found that `publish_episode` calls `dispatch_http` which blocks the actor thread (synchronous `dispatch_capability` return; the async variant `dispatch_http_async`'s doc explicitly says 'does not block the actor thread'). An N-episode catalog flip would freeze all reactivity for minutes

## Decision

Replace the synchronous loop with per-episode self-enqueue: `update_owned` dispatches N `publish_episode` actions via `nmp_app_dispatch_action` (which only validates + enqueues an `ActorCommand` and returns immediately). Each episode publishes in its own later actor tick, yielding between them

## Consequences

- D8 responsiveness preserved — a 50-100 episode flip stays responsive
- D0 policy stays in the kernel (the backfill logic, not the shell)
- Old Swift per-tick loop deleted from `LiveAgentOwnedPodcastManager.swift`
- Response now carries `episodes_queued` and `episodes_accepted` counts

## Open Tail

*(none)*

## Evidence

- transcript lines 3976-4048
- transcript lines 4107-4131

