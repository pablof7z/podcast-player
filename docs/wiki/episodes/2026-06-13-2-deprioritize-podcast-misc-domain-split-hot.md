---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - projection-perf
  - podcast-misc
  - domain-rev-split
supersedes:
  - 2026-06-13-4-deprioritize-per-domain-misc-split-hot
related_claims: []
source_lines:
  - 8479-8487
captured_at: 2026-06-13T04:09:51Z
---

# Episode: Deprioritize podcast.misc domain split — hot path already killed by #425

## Prior State

The per-domain projection split (promoting heavy substates like agent/wiki/clips out of `podcast.misc`) was assumed to be the highest-conviction cycle-10 headline — a contract-heavy PR to eliminate a perceived whole-library rebuild on every tick.

## Trigger

The cycle-10 planner verified against the code that #425 (slice-local domain payload builders) already killed the hot path: the misc domain rev only advances on low-frequency wiki/knowledge/picks edits (6+3+1 bumps total). High-frequency mutators (agent-chat streaming, voice, clips, comments) use `SnapshotUpdateSignal::bump()` which touches only the GLOBAL rev, not domain counters — so their tokens produce frames where every domain closure sees an unchanged domain rev and returns None (no rebuild fires).

## Decision

Explicitly deprioritize the misc domain split. It would be pure server-side hygiene requiring matching iOS+Android frame structs + merge code (contract-sensitive: snake_case + golden + real-bump gates) for a rebuild that only fires on manual wiki/pick edits. Not worth a cycle headline.

## Consequences

- Cycle-10 reoriented toward Android conversations parity (consuming already-shipped `podcast.social` kernel work) and BACKLOG truthfulness sweep instead.
- A latent correctness question exists (does the push frame ever carry agent-chat/voice deltas if they never advance a domain rev?) but the pull path remains the hydration fallback and shells re-pull on global-rev frames, so it is not a regression.
- BACKLOG truthfulness sweep (#427) further revealed that `social-publish-relay-target` already routes via `target: Auto` (NMP pool-aware), not a hardcoded relay — further shrinking assumed work.

## Open Tail

- One-line BACKLOG note about the push-frame correctness question for agent-chat/voice deltas that never advance a domain rev.

## Evidence

- transcript lines 8479-8487

