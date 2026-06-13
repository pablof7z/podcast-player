---
type: episode-card
date: 2026-05-10
session: c6722edd-ee95-4534-9e81-9bb6b5dc60d6
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c6722edd-ee95-4534-9e81-9bb6b5dc60d6.jsonl
salience: product
status: active
subjects:
  - intro-outro-backfill
  - ai-chapter-compiler
  - idempotence-gate
supersedes: []
related_claims: []
source_lines:
  - 3838-3838
  - 3839-3841
captured_at: 2026-06-12T11:50:37Z
---

# Episode: Backfill strategy: skip old episodes for intro/outro markers

## Prior State

The initial revised plan proposed re-calling the LLM once per back-catalog episode to backfill `introEnd`/`outroStart` via a new `introOutroDetected` idempotence gate

## Trigger

User chose 'Skip old episodes' when presented with three backfill options (one re-call per old episode, accept the gap, or bump compileVersion)

## Decision

Old episodes with already-compiled `adSegments` will NOT be re-called. Only new compilations (where `adSegments == nil`) produce intro/outro markers. The `introOutroDetected` flag becomes unnecessary and is dropped.

## Consequences

- No extra LLM spend on back-catalog episodes
- Old episodes' intros/outros stay bare until they're re-compiled for other reasons
- Idempotence gate remains `episode.adSegments == nil` — unchanged from current behavior

## Open Tail

*(none)*

## Evidence

- transcript lines 3838-3838
- transcript lines 3839-3841

