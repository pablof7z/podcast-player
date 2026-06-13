---
type: episode-card
date: 2026-06-08
session: c33b9adb-9d1a-4717-9314-b45a61e6cbc3
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c33b9adb-9d1a-4717-9314-b45a61e6cbc3.jsonl
salience: architecture
status: active
subjects:
  - swift-kernel-observation
  - action-helpers
  - reactive-await
supersedes: []
related_claims: []
source_lines:
  - 383-389
captured_at: 2026-06-12T13:31:41Z
---

# Episode: Swift action-helper polling replaced by reactive @Observable awaiters

## Prior State

Swift code used Task.sleep(300ms) polling loops in action helpers to wait for kernel state changes — a pattern that could hang forever when awaited Rust state never arrives (onChange never fires, deadline never re-checked).

## Trigger

Finding that the polling awaiters had a genuine hang condition: without a timeout racer, if onChange never fires for the awaited state, the awaiter parks indefinitely with no deadline re-check.

## Decision

Replaced Task.sleep(300ms) loops with @Observable reactive awaiters + timeout racers (OneShotResume). The reactive path subscribes to state changes and the timeout racer ensures the awaiter never parks forever.

## Consequences

- Eliminated all polling loops in Swift action helpers
- Hang condition fixed — awaiters now have bounded lifetime via timeout racers
- Surfaced pre-existing PodcastrTests compile regression (5 test files drifted), logged in BACKLOG as P0

## Open Tail

- PodcastrTests target is red on main — needs follow-up fix

## Evidence

- transcript lines 383-389

