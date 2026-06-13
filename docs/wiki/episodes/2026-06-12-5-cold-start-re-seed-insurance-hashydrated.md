---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - cold-start-race
  - kernel-model
  - push-pull-interaction
supersedes:
  - 2026-06-12-5-cold-start-hashydrated-guard-against-partial
related_claims: []
source_lines:
  - 4930-4950
captured_at: 2026-06-12T15:07:20Z
---

# Episode: Cold-start re-seed insurance — hasHydrated flag

## Prior State

The iOS push path used a strict `update.rev > lastProcessedRev` monotonic guard for all frames, including the initial cold-start pull.

## Trigger

The #403 Opus review identified a narrow race: if the kernel's first push frame is partial (omits library) and wins the race against the still-decoding startup pull, the push sets `lastProcessedRev` to a value that causes the pull to be dropped, leaving an empty library.

## Decision

Introduce a `hasHydrated: Bool` flag. On cold-start pull (the first pull), the guard uses `>=` instead of `>`, allowing the redundant full pull to re-seed even if a partial push already consumed the rev. After `hasHydrated = true`, the normal `>` monotonic guard is restored. `resetAndRestart()` also resets `hasHydrated = false`.

## Consequences

- Eliminates the narrow blank-library race on cold start
- No steady-state behavior change — after first hydration, the strict `>` guard applies
- Kernel restart with rev reset to 1 is handled correctly (fresh `KernelModel` also starts tracker at 0)

## Open Tail

*(none)*

## Evidence

- transcript lines 4930-4950

