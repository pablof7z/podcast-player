---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - swift-delete-verification
  - test-target-glob
  - build-for-testing
supersedes:
  - 2026-06-12-4-delete-swift-prs-must-run-real
related_claims: []
source_lines:
  - 6401-6424
  - 6454-6470
captured_at: 2026-06-12T22:54:33Z
---

# Episode: Swift file deletion requires test-target build verification

## Prior State

Verifying Swift file deletions with an app-target-only build (xcodebuild build or Swift compilation check). The test target (PodcastrTests) globs AppTests/Sources/**, so orphaned test files referencing deleted production symbols compiled fine in the app target but broke the test target.

## Trigger

BlossomUploaderTests.swift (260 lines) was left orphaned after deleting BlossomUploader.swift — the third occurrence of this trap (after #413 and an earlier incident). The agent's 'Swift build passed' only verified the app target, not build-for-testing.

## Decision

When deleting Swift files, always run xcodebuild build-for-testing (or tuist generate + build-for-testing), not just the app target. Grep for orphaned symbol references across App/ and AppTests/ as a secondary check. Recorded as a durable rule in project memory.

## Consequences

- Prevents the recurring orphaned-test-file build breakage pattern
- build-for-testing catches AppTests/Sources/** glob inclusions that app-only builds miss
- Rule recorded in memory (swift_delete_needs_test_target_build.md) for future implementer/reviewer checklists

## Open Tail

*(none)*

## Evidence

- transcript lines 6401-6424
- transcript lines 6454-6470

