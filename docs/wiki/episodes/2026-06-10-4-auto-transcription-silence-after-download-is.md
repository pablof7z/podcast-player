---
type: episode-card
date: 2026-06-10
session: 681fa743-322c-4b1a-8e99-81a97aa1a904
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/681fa743-322c-4b1a-8e99-81a97aa1a904.jsonl
salience: root-cause
status: active
subjects:
  - transcription-auto-ingest
  - auto-fallback-to-scribe
supersedes:
  - 2026-06-10-1-pipeline-diagnostics-must-explain-configuration-state
related_claims: []
source_lines:
  - 1-1
  - 127-136
  - 2040-2070
captured_at: 2026-06-12T13:42:09Z
---

# Episode: Auto-transcription silence after download is deliberate, not a bug

## Prior State

User observed that after an episode finishes downloading, transcription does not auto-fire, and suspected it might not be possible or might be broken.

## Trigger

Investigation of the transcript ingest pipeline (TranscriptIngestService, TranscriptIngestService+AutoIngest, effectiveTranscriptionEnabled) revealed the gating logic: auto-ingest checks (1) the podcast-level effective transcription enabled flag, (2) whether the episode has a publisher transcript URL, and (3) the autoFallbackToScribe setting. If AI fallback is OFF, transcription is deliberately skipped — this is by design, not a bug.

## Decision

Rather than changing the auto-ingest behavior, the fix was to make the existing configuration state visible in the Diagnostics panel so the user understands WHY transcription isn't firing. The 'Pipeline configuration' panel now explicitly states the verdict (e.g., 'Won't transcribe automatically — AI transcription fallback is OFF').

## Consequences

- No change to auto-ingest logic — the existing gates remain authoritative
- The user's confusion is resolved by surfacing the configuration, not by changing the behavior
- The effectiveSttProvider and hasLoadedKey checks are now exposed in the diagnostics UI

## Open Tail

*(none)*

## Evidence

- transcript lines 1-1
- transcript lines 127-136
- transcript lines 2040-2070

