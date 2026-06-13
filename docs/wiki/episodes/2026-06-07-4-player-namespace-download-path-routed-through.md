---
type: episode-card
date: 2026-06-07
session: 9833dc25-72f9-4d4f-98d9-df476ead3e6d
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9833dc25-72f9-4d4f-98d9-df476ead3e6d.jsonl
salience: architecture
status: active
subjects:
  - player-download
  - episode-events
  - download-queue
supersedes:
  - 2026-06-07-2-auto-download-evaluation-fixed-cold-start
related_claims: []
source_lines:
  - 1856-1983
captured_at: 2026-06-12T13:27:03Z
---

# Episode: Player-namespace download path routed through canonical event-emitting helper

## Prior State

handle_player_download (PlayerAction::Download) enqueued directly via handle_download_command, bypassing the start_episode_download helper that emits download.requested/started events.

## Trigger

Advisor review flagged that any Swift download using the player namespace would produce no events — the exact same bug the session was fixing, silently re-introduced by having two code paths.

## Decision

Routed handle_player_download through the canonical start_episode_download helper, so all download initiators share the queue, concurrency control, and event emission.

## Consequences

- All download paths now emit the same event sequence regardless of initiator namespace
- No silent event-tracking gap for player-initiated downloads

## Open Tail

*(none)*

## Evidence

- transcript lines 1856-1983

