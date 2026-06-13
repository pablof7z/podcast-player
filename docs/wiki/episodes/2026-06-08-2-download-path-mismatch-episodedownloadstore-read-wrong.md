---
type: episode-card
date: 2026-06-08
session: 7e35e451-81d2-4832-8c6e-34d44fc29e12
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7e35e451-81d2-4832-8c6e-34d44fc29e12.jsonl
salience: root-cause
status: active
subjects:
  - download-store
  - transcription-pipeline
  - on-device-stt
supersedes:
  - 2026-06-08-1-download-path-mismatch-broke-transcription-audio
related_claims: []
source_lines:
  - 2407-2409
captured_at: 2026-06-12T13:35:49Z
---

# Episode: Download path mismatch: EpisodeDownloadStore read wrong directory

## Prior State

On-device transcription silently failed because EpisodeDownloadStore.exists() checked podcastr/downloads/ but DownloadCapability wrote files to Downloads/ — the path mismatch meant exists() always returned false and on-device STT bailed at the file-existence guard

## Trigger

Agent read on-disk sim event files and confirmed download.requested→started→finished all persisted correctly, but TranscriptIngestService returned at silent guards; pinning the root cause as a path mismatch (B1) rather than an event-emission problem (B2)

## Decision

Peer PR #351 fixed the path mismatch; this agent chose observability-only scope (no duplicate fix) and instead added skip events so future mismatches are visible immediately

## Consequences

- On-device STT now starts after download (files are found)
- This unmasked a dormant bug in AppleNativeSTTClient that had never been exercised before
- Future silent exits from the pipeline will surface in Diagnostics via transcript.skipped events

## Open Tail

*(none)*

## Evidence

- transcript lines 2407-2409

