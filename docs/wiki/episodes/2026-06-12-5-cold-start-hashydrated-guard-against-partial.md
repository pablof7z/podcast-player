---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - cold-start
  - hasHydrated
  - ios-bridge
  - push-pull-race
supersedes: []
related_claims: []
source_lines:
  - 4762-4779
  - 4930-4951
captured_at: 2026-06-12T14:47:13Z
---

# Episode: Cold-start hasHydrated guard against partial-first-push race

## Prior State

Both push and pull paths shared `lastProcessedRev`. If the kernel's first push frame was partial (omitted the library domain) and won the race against the still-decoding startup pull, the push would set `compositeUpdate.rev = maxDomainRev` and `lastProcessedRev`, causing the pull to be dropped by `update.rev > lastProcessedRev` — leaving an empty library.

## Trigger

The #403 review identified this narrow race: startup pull runs async on `snapshotDecodeQueue`, and a partial first push could consume the rev before the pull finishes.

## Decision

Add a `hasHydrated` flag to `KernelModel`. On the first cold-start pull, use `>=` to allow re-seeding even if a partial push already consumed the rev. After `hasHydrated = true`, the normal `>` monotonic guard is restored. `resetAndRestart()` also resets `hasHydrated = false`.

## Consequences

- No blank-library window even if a partial first push beats the startup pull
- Steady-state behavior unchanged: after first hydration, `>` guard applies
- Kernel reset (rev starts at 1) handled by resetting `hasHydrated` alongside `lastProcessedRev`

## Open Tail

*(none)*

## Evidence

- transcript lines 4762-4779
- transcript lines 4930-4951

