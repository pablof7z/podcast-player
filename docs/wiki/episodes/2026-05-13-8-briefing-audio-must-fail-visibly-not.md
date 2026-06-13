---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: product
status: active
subjects:
  - briefing-player
  - audio-host
  - missing-audio
supersedes: []
related_claims: []
source_lines:
  - 75-86
  - 695-712
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Briefing audio must fail visibly, not silently

## Prior State

BriefingPlayerView fell back to /dev/null when audio was missing and the share button was a dead no-op stub.

## Trigger

Audit found FakeBriefingPlayerHost as the only production audio host and the dead share button.

## Decision

Missing-audio banner replaces the /dev/null silent fallback. Dead share button removed entirely.

## Consequences

- Users see a clear message when briefing audio is unavailable instead of silence
- Removed a share affordance that did nothing

## Open Tail

- FakeBriefingPlayerHost is still the only production host — NowPlaying/CarPlay for briefings still blocked on AudioEngine exposing BriefingPlayerHostProtocol
- Hold-to-ask still returns fake echo 'You asked: ...' instead of a real agent answer

## Evidence

- transcript lines 75-86
- transcript lines 695-712

