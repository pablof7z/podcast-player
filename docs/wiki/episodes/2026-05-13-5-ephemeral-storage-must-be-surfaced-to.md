---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: product
status: active
subjects:
  - ephemeral-storage
  - transcript-store
  - briefings-data-loss
supersedes: []
related_claims: []
source_lines:
  - 536-560
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Ephemeral storage must be surfaced to the user

## Prior State

TranscriptStore and BriefingsViewModel silently fell back to temporaryDirectory when Application Support was unavailable — data disappeared on restart with no user awareness.

## Trigger

Audit found silent tmp-dir fallbacks with no logging or UI indication.

## Decision

TranscriptStore logs .error with full description; BriefingsViewModel logs .error; BriefingsView shows a top-of-scroll warning banner ('Briefings stored temporarily — will be lost when the app restarts').

## Consequences

- Users are now aware their data is ephemeral before it vanishes
- Console.app shows actionable error messages for debugging
- TranscriptStore banner was intentionally omitted (v1: logging only per spec)

## Open Tail

- No TranscriptStore UI banner — only logging for v1

## Evidence

- transcript lines 536-560

