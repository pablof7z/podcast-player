---
type: episode-card
date: 2026-05-13
session: 9f2d26f1-3e71-46b0-83d8-cc9895be3a8e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9f2d26f1-3e71-46b0-83d8-cc9895be3a8e.jsonl
salience: product
status: active
subjects:
  - transcription-source-enum
  - nip-90-transcription
  - agent-tts
supersedes: []
related_claims: []
source_lines:
  - 21-21
  - 66-66
captured_at: 2026-06-12T12:09:31Z
---

# Episode: New .nostr Enum Case Required — .other Already Taken by Agent-TTS

## Prior State

TranscriptSource and TranscriptState.Source enums had no Nostr variant. Source.other might have seemed available for overloading.

## Trigger

Opus agent identified that Source.other is already occupied by AgentTTSComposer for agent-generated TTS episodes.

## Decision

Add .nostr as a distinct new case to both TranscriptSource (Transcript.swift:44-50) and TranscriptState.Source (TranscriptState.swift:23-30). Do not repurpose .other.

## Consequences

- Two enums must be updated in lockstep
- Any switch statements on these enums will need new cases
- Source semantics remain unambiguous — .nostr ≠ .other (TTS)

## Open Tail

*(none)*

## Evidence

- transcript lines 21-21
- transcript lines 66-66

