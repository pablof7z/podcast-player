---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: active
subjects:
  - ci-sim-destination
  - ios-test-gate
supersedes: []
related_claims: []
source_lines:
  - 3488-3513
  - 3538-3599
captured_at: 2026-06-12T11:45:46Z
---

# Episode: CI iOS test gate silently dead from hardcoded simulator name

## Prior State

CI's `run_tests.sh` hardcoded `-destination "platform=iOS Simulator,name=iPhone 17,OS=latest"`, and the iOS "Build and Test" check was assumed to be a meaningful quality gate.

## Trigger

PR #390's "Build and Test" check failed with `xcodebuild: error: Unable to find a device matching ... { name:iPhone 17 }` — the CI runner has no iPhone 17 simulator. This had broken twice before (iPhone 16 removed, then iPhone 17 added in code but never installed).

## Decision

Replace hardcoded name with runtime UDID discovery: prefer a simulator ending in ` ci` (the runner's purpose-built sim), fall back to any available iPhone simulator, loud-fail with device list if none found. PR #392 merged.

## Consequences

- The iOS test gate is restored — next PR's Build-and-Test will be the proof
- Future Xcode/simulator bumps on the runner won't re-break CI
- PR #390 was correctly merged despite the CI failure (it was environmental, not a code defect; only Migration lint was a required check)

## Open Tail

*(none)*

## Evidence

- transcript lines 3488-3513
- transcript lines 3538-3599

