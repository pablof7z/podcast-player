---
type: episode-card
date: 2026-06-08
session: 7e35e451-81d2-4832-8c6e-34d44fc29e12
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7e35e451-81d2-4832-8c6e-34d44fc29e12.jsonl
salience: product
status: active
subjects:
  - transcript-pipeline
  - diagnostics
  - episode-events
supersedes: []
related_claims: []
source_lines:
  - 1-1
  - 2407-2428
captured_at: 2026-06-12T13:35:49Z
---

# Episode: Transcript skip observability: silent guard points now emit events

## Prior State

TranscriptIngestService had four guard points (category opt-out, AI transcription off, forced provider missing key, on-device audio not on disk) that returned silently without emitting any event, making it impossible for users to understand why transcription didn't run

## Trigger

User reported seeing download completion in Diagnostics but zero indication of whether transcription was kicked off — no event log generated whatsoever

## Decision

Added PodcastStore::record_transcript_skip(episode_id, reason) that emits transcript.skipped events with reason detail; idempotent per reason (collapses repeat skips since ingest() re-fires on every episode-detail open); no rev bump (skip changes no projected state); skip status does not touch set_transcript_status to avoid corrupting transcriptState

## Consequences

- Diagnostics sheet now explains why transcription didn't run instead of showing silence after download.finished
- Repeat skips on re-ingest collapse to a single event rather than spamming the log
- Skip events are read-only observability — they cannot alter transcript readiness state

## Open Tail

*(none)*

## Evidence

- transcript lines 1-1
- transcript lines 2407-2428

