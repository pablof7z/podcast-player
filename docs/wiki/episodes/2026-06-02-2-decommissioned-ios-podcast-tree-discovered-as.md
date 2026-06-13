---
type: episode-card
date: 2026-06-02
session: a6320d4d-f2c8-4a8b-a21a-d71f5af73509
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a6320d4d-f2c8-4a8b-a21a-d71f5af73509.jsonl
salience: root-cause
status: active
subjects:
  - build-target
  - ios-legacy-tree
  - accessibility-identifiers
supersedes: []
related_claims: []
source_lines:
  - 630-634
captured_at: 2026-06-12T12:58:50Z
---

# Episode: Decommissioned ios/Podcast/ tree discovered as dead code path

## Prior State

Belief that ios/Podcast/Podcast/ was the compiled iOS source tree; a11y IDs and Maestro test references were expected to go there.

## Trigger

PR #235 agent checked Project.swift L69 and found the app compiles from App/Sources/** only; WIP.md L30 confirms ios/Podcast/ is decommissioned legacy code. Existing Maestro flows already reference appId io.f7z.podcast (the App/Sources app).

## Decision

All iOS shell modifications (a11y IDs, view changes) must target App/Sources/, not ios/Podcast/Podcast/. The 18 a11y identifiers were placed in the live compilation tree.

## Consequences

- Future agents must not modify ios/Podcast/Podcast/ for feature work — it compiles but never ships
- Any code in the legacy tree is effectively dead and should not be trusted for correctness
- Prevents a class of bug where changes are made to files that never reach the simulator or App Store

## Open Tail

- The legacy ios/Podcast/ directory still exists and could mislead future agents; a cleanup or README marker may be warranted

## Evidence

- transcript lines 630-634

