---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - domain-projections
  - podcast-misc
  - perf-architecture
supersedes: []
related_claims: []
source_lines:
  - 8467-8526
captured_at: 2026-06-13T03:49:37Z
---

# Episode: Deprioritization of podcast.misc domain split

## Prior State

The per-domain projection split (promoting heavy substates out of podcast.misc into separate podcast.agent/wiki/clips domains) was the assumed next architecture headline, believed to be necessary for performance.

## Trigger

Cycle-10 planner verified against the code that the expensive build_misc_payload only runs when the misc domain rev advances, and the only sites that advance misc are low-frequency (wiki: 6 bumps, knowledge: 3, picks: 1). High-frequency mutators (agent-chat streaming, voice, clips, comments) use signal.bump() which touches only the GLOBAL rev — every domain closure sees an unchanged domain rev and returns None, so no rebuild fires. #425 already killed the hot path.

## Decision

Explicitly deprioritize the podcast.misc split. It would be a contract-heavy PR (iOS+Android frame structs, snake_case, golden, real-bump gates) for near-zero performance gain — the remaining rebuild only fires on manual wiki/pick edits.

## Consequences

- Saves a contract-sensitive multi-platform PR for negligible perf gain
- A latent correctness note added to BACKLOG about whether push frames ever carry agent-chat/voice deltas
- Cycle-10 headline shifted to Android social/conversations feature parity instead

## Open Tail

- One-line BACKLOG note about whether signal.bump() push frames carry sufficient deltas for agent-chat/voice — the pull path remains the hydration fallback

## Evidence

- transcript lines 8467-8526

