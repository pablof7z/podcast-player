---
type: episode-card
date: 2026-05-10
session: c6722edd-ee95-4534-9e81-9bb6b5dc60d6
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c6722edd-ee95-4534-9e81-9bb6b5dc60d6.jsonl
salience: reversal
status: active
subjects:
  - intro-outro-detection
  - ai-chapter-compiler
  - episode-model
  - ad-skip-parity
supersedes: []
related_claims: []
source_lines:
  - 3421-3425
  - 3526-3544
captured_at: 2026-06-12T11:50:37Z
---

# Episode: Intro/outro reframed from hardcoded per-show durations to LLM-detected per-episode markers

## Prior State

The initial plan proposed `skipIntro`/`skipOutro` as per-show overrides for skip-button durations (hardcoded seconds like Pocket Casts), stored as fields on `ShowPlaybackProfile`

## Trigger

User explicitly corrected: 'we can get the llm to tell us what's the intro/outro — so we should just ask the llm to flag those times like we do with ads, so, make it like pocket cast, just not based on a hardcoded time amount'

## Decision

Intro/outro detection reframed as per-episode LLM-detected scalars (`introEnd: TimeInterval?`, `outroStart: TimeInterval?`) on `Episode`, extending the existing `AIChapterCompiler` single-pass pipeline with two new JSON keys. NOT stored as profile fields or `AdKind` variants. Auto-skip wiring mirrors `PlaybackState+AdSkip.swift` exactly.

## Consequences

- Profile collapsed from 5 fields to 2 (speed + autoPlayNext), growing to 4 only when `autoSkipIntro`/`autoSkipOutro` toggles land in commit 5
- Skip-button durations (`skipForwardSeconds`/`skipBackwardSeconds`) stay global — no per-show override needed
- Outro semantics fixed as 'fire end-of-episode early' (seek to duration) — composes with `autoPlayNext`, `autoMarkPlayedOnFinish`, and sleep-timer end-of-episode mode for free
- Intro/outro are structurally separate from ads (different semantics: show structure vs commercial content) — no `AdKind` extension, no `adSegments` contamination

## Open Tail

- A future 'Skip intro' scrubber chip (mirroring `PlayerPrerollSkipButton`) is optional follow-up, not in v1

## Evidence

- transcript lines 3421-3425
- transcript lines 3526-3544

