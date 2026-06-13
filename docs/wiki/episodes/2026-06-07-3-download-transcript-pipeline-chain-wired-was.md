---
type: episode-card
date: 2026-06-07
session: 9833dc25-72f9-4d4f-98d9-df476ead3e6d
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9833dc25-72f9-4d4f-98d9-df476ead3e6d.jsonl
salience: root-cause
status: active
subjects:
  - transcript-ingest
  - download-completion
  - pipeline-chain
supersedes: []
related_claims: []
source_lines:
  - 114-124
  - 1517-1613
  - 2425-2426
captured_at: 2026-06-12T13:27:03Z
---

# Episode: Download→transcript pipeline chain wired (was a phantom comment)

## Prior State

Code comment in TranscriptIngestService described a 'post-download re-entry into ingest()' as the intended design, but this hook was never wired. Download completion just stamped the file path and stopped.

## Trigger

Discovery that the documented download→transcript chain was a phantom — evaluateAutoIngest was defined but never called, and no post-download path re-entered ingest().

## Decision

Wired DownloadCapability+Delegate.swift completion handler to call TranscriptIngestService.ingest() after file move, with a readiness guard (EpisodeDownloadStore.shared.exists check) to avoid race with the kernel projection. ingest() self-deduplicates via inFlight set.

## Consequences

- Downloaded episodes automatically begin transcription
- Transcript-ready then triggers chapter compilation and ad detection via existing handler chain
- Race-safe: ingest() reads file existence directly (not kernel projection), and dedup prevents double-kick

## Open Tail

- Not live-verified end-to-end: simulator cannot run Apple on-device STT, and the test episode had no publisher transcript URL. Kickoff is wired and tested by construction but not verified through to transcript.ready in running app.

## Evidence

- transcript lines 114-124
- transcript lines 1517-1613
- transcript lines 2425-2426

