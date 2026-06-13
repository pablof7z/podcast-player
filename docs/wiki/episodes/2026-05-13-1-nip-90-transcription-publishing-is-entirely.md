---
type: episode-card
date: 2026-05-13
session: 9f2d26f1-3e71-46b0-83d8-cc9895be3a8e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9f2d26f1-3e71-46b0-83d8-cc9895be3a8e.jsonl
salience: root-cause
status: superseded
subjects:
  - nip-90-transcription
  - transcription-pipeline
supersedes: []
related_claims: []
source_lines:
  - 7-9
captured_at: 2026-06-12T12:09:31Z
---

# Episode: NIP-90 Transcription Publishing Is Entirely Absent

## Prior State

The session was launched to discover how transcriptions are published as NIP-90 Nostr events, implying an expectation that some implementation or convention might already exist.

## Trigger

Exhaustive search by NIP-90 keyword, DVM terminology, kind numbers (5000–5999, 6000–6999, 7000), and transcription+nostr combinations found zero matches.

## Decision

No NIP-90 transcription publishing exists in the codebase. The transcription pipeline is entirely HTTP-based (ElevenLabs/AssemblyAI/Apple STT) with local storage in TranscriptStore. Any NIP-90 work is greenfield.

## Consequences

- All NIP-90 transcription publishing code must be written from scratch
- No existing NIP-90 patterns in the codebase to follow — must adapt from other Nostr services (comments, relay)

## Open Tail

*(none)*

## Evidence

- transcript lines 7-9

