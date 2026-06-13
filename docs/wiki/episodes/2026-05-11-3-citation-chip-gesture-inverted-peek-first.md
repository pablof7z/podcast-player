---
type: episode-card
date: 2026-05-11
session: 7f076ca6-6975-44ae-9848-d41832e499f0
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7f076ca6-6975-44ae-9848-d41832e499f0.jsonl
salience: product
status: active
subjects:
  - citation-chip
  - wiki-ux
  - gesture-inversion
supersedes: []
related_claims: []
source_lines:
  - 5219-5221
captured_at: 2026-06-12T11:54:11Z
---

# Episode: Citation chip gesture inverted: peek-first, provenance-before-commitment

## Prior State

CitationChip tap dispatched playback (play_episode_at via PlaybackState); long-press showed the CitationPeekSheet for auditioning the cited 12 seconds. Icon was `play.fill`.

## Trigger

Phase 2a design decision — users should see citation provenance before committing to playback

## Decision

Tap → CitationPeekSheet (peek-first); long-press → dispatch playback. Icon flipped from `play.fill` to `quote.bubble`. Accessibility hint updated.

## Consequences

- Users always see where a citation comes from before accidentally jumping playback position
- Long-press is now the 'commit' gesture for playing at a citation timestamp
- Accessibility hint must reflect the swapped semantics

## Open Tail

*(none)*

## Evidence

- transcript lines 5219-5221

