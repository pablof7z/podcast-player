---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - podcast-misc
  - domain-projection-split
  - projection-performance
supersedes:
  - 2026-06-13-4-deprioritization-of-podcast-misc-domain-split
related_claims: []
source_lines:
  - 8476-8487
captured_at: 2026-06-13T03:58:09Z
---

# Episode: Deprioritize per-domain misc split — hot path already eliminated

## Prior State

The cycle-9 planner identified finishing the per-domain projection split (promoting heavy substates out of podcast.misc) as the highest-conviction leftover for cycle-10, assuming it was a significant performance win.

## Trigger

Cycle-10 planner investigated the actual rev-bump sites and found that the high-frequency mutators everyone feared (agent-chat streaming, voice, clips, comments) do NOT advance the misc domain rev — they use signal.bump() which touches only the global rev, so their tokens produce frames where every domain closure sees an unchanged domain rev and returns None. The misc rev only advances on low-frequency wiki (6 bumps), knowledge (3), and picks (1) edits.

## Decision

Explicitly deprioritize the per-domain misc split. It would be pure server-side hygiene requiring matching iOS+Android frame structs + merge code (contract-sensitive: snake_case + golden + real-bump gates) for a rebuild that only fires on manual wiki/pick edits — near-zero performance gain after #425 killed the hot path.

## Consequences

- A contract-heavy PR with near-zero performance payoff is avoided
- The misc domain rev continues to advance only on wiki/knowledge/picks edits, which are low-frequency
- Latent correctness question: the push frame never carries agent-chat/voice deltas via domain revs (they use global signal), so the pull path remains the hydration fallback — not a regression but worth noting

## Open Tail

- Whether agent-chat/voice deltas need their own domain rev to propagate incrementally via the push frame

## Evidence

- transcript lines 8476-8487

