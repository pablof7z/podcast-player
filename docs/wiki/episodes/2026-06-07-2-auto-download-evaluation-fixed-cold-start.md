---
type: episode-card
date: 2026-06-07
session: 9833dc25-72f9-4d4f-98d9-df476ead3e6d
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9833dc25-72f9-4d4f-98d9-df476ead3e6d.jsonl
salience: product
status: superseded
subjects:
  - auto-download
  - episode-download
  - cold-start
supersedes: []
related_claims: []
source_lines:
  - 102-102
  - 2424-2431
captured_at: 2026-06-12T13:27:03Z
---

# Episode: Auto-download evaluation fixed — cold-start + existing-episode backfill

## Prior State

Auto-download evaluation only ran during feed refresh (which cold-start skips) and only considered brand-new GUID episodes. Enabling auto-download on an existing show downloaded nothing.

## Trigger

Finding that auto-download never fires: evaluation was gatekept behind feed-refresh and excluded existing library episodes.

## Decision

Added auto_download_evaluate action dispatched on cold start and on enable-toggle. Added a current-library backfill scan that evaluates all undownloaded episodes against per-podcast auto-download settings. All download initiators routed through one canonical start_episode_download helper (queue, concurrency control, event logging).

## Consequences

- Enabling auto-download on an existing subscription now immediately begins downloading eligible episodes
- All download paths (user-initiated, auto-download, player-namespace) share the same queue and emit the same events
- latestN setting collapsed to a bool in kernel; depth semantics remain in Swift

## Open Tail

*(none)*

## Evidence

- transcript lines 102-102
- transcript lines 2424-2431

