---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - actor-stall
  - d8-invariant
  - blossom-upload
  - publish-episode
supersedes:
  - 2026-06-12-3-d8-actor-stall-in-owned-podcast
related_claims: []
source_lines:
  - 3976-4048
captured_at: 2026-06-12T12:10:51Z
---

# Episode: D8 actor-stall regression in owned-podcast backfill

## Prior State

The Swift `LiveAgentOwnedPodcastManager` loop dispatched one `kernelPublishEpisode` per tick, yielding between episodes — preserving the D8 invariant (actor thread must be cheap, non-blocking).

## Trigger

PR #397 moved the per-episode kind:54 backfill into `update_owned` on the kernel side as a synchronous `for episode_id in episode_ids { publish_episode(handler, episode_id) }` loop. Inline review revealed that `publish_episode` calls `dispatch_http` (not `dispatch_http_async`), which blocks the actor thread on each Blossom upload + sign + broadcast round-trip. An N-episode catalog flip would freeze all reactivity for minutes.

## Decision

PR #397 sent back for rework: must use per-episode command enqueueing (fire-and-forget via `dispatch_http_async` or command dispatch) to preserve D8. The kernel-side policy (D0: Rust owns state) is kept; only the synchronous loop must become asynchronous.

## Consequences

- Any kernel code calling `dispatch_http` in a loop is a D8 violation — must use async path or enqueue separate commands
- The `dispatch_http` vs `dispatch_http_async` split is a load-bearing invariant that future implementors must be aware of
- Owned-podcast visibility flip remains a valid D0 move; only the synchronous serialization of N network calls is rejected

## Open Tail

- PR #397 must be reworked before merge — enqueue per-episode publish commands instead of looping synchronously

## Evidence

- transcript lines 3976-4048

