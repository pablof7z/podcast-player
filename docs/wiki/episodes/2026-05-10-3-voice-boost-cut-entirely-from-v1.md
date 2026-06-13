---
type: episode-card
date: 2026-05-10
session: c6722edd-ee95-4534-9e81-9bb6b5dc60d6
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c6722edd-ee95-4534-9e81-9bb6b5dc60d6.jsonl
salience: product
status: active
subjects:
  - voice-boost
  - audio-engine
  - show-playback-profile
supersedes: []
related_claims: []
source_lines:
  - 3421-3421
captured_at: 2026-06-12T11:50:37Z
---

# Episode: Voice boost cut entirely from v1 — no audio infrastructure exists

## Prior State

Initial plan included `voiceBoost: Bool?` as a profile field, with a disabled 'Coming soon' toggle in the editor

## Trigger

User answered the decision question: 'Cut from v1 entirely'

## Decision

Remove `voiceBoost` field entirely from `ShowPlaybackProfile` and all UI. No audio-unit graph, no `AVMutableAudioMix`, no `MTAudioProcessingTap` work in this batch.

## Consequences

- Profile is simpler at launch (2 fields instead of 3+)
- Adding voice boost later requires first building an audio-processing pipeline into `AudioEngine` (currently raw `AVPlayer`) — a separate architectural exercise

## Open Tail

*(none)*

## Evidence

- transcript lines 3421-3421

