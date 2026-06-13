---
type: episode-card
date: 2026-06-10
session: 681fa743-322c-4b1a-8e99-81a97aa1a904
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/681fa743-322c-4b1a-8e99-81a97aa1a904.jsonl
salience: product
status: active
subjects:
  - episode-diagnostics
  - transcription-events
  - chapters-events
supersedes: []
related_claims: []
source_lines:
  - 127-131
  - 1479-1482
  - 1813-1877
  - 2019-2038
captured_at: 2026-06-12T13:42:09Z
---

# Episode: Diagnostic events must attribute the responsible provider and model

## Prior State

Transcript, chapter, and playback events in the diagnostics log were anonymous — they did not identify which STT provider (ElevenLabs Scribe, Apple on-device, AssemblyAI, Whisper) produced the transcript, nor which LLM model identified chapters. The user saw 'Transcribing audio' or 'Chapters identified' without attribution.

## Trigger

Same user question — to understand the pipeline, events must name the responsible service so the user can trace which provider actually ran (or failed).

## Decision

Enriched all transcript lifecycle events to carry the provider display name (via STTProvider.displayName → TranscriptState.Source mapping) and the model name. Chapter-identification events now name the LLM model (e.g. 'DeepSeek Flash') or honestly say 'equal-length fallback' when Scribe was unreachable. The ready event includes source + character count + chunk count.

## Consequences

- Transcript attempt events now read 'Transcribing audio · ElevenLabs Scribe' or 'Transcribing audio · Apple on-device'
- Chapter events read 'Chapters identified · DeepSeek Flash' or 'Equal-length fallback (model unavailable)'
- The transcript report FFI (sendTranscriptReport) gained a source parameter to thread the provider name through the kernel pipeline
- Kernel-side event recording now carries provider and model metadata through to the event store

## Open Tail

*(none)*

## Evidence

- transcript lines 127-131
- transcript lines 1479-1482
- transcript lines 1813-1877
- transcript lines 2019-2038

