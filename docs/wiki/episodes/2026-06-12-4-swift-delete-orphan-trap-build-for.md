---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: active
subjects:
  - swift-delete-workflow
  - test-target-build
supersedes:
  - 2026-06-12-3-swift-file-deletion-requires-test-target
related_claims: []
source_lines:
  - 6452-6470
captured_at: 2026-06-12T23:56:39Z
---

# Episode: Swift-delete orphan trap: build-for-testing is mandatory

## Prior State

Deleting Swift source files and running an app-target build (`xcodebuild build` or `tuist generate` + app scheme) appeared sufficient to verify no compilation errors. Orphaned test files referencing deleted symbols went undetected.

## Trigger

PR #413 (AIChapterCompiler deletion) orphaned `overlapsAd` extension; PR #418 (BlossomUploader deletion) orphaned `BlossomUploaderTests.swift` (260 lines). Both passed app-only builds but broke the test target. Same pattern, third occurrence counting a prior incident.

## Decision

After deleting any Swift file, always run `xcodebuild build-for-testing` (not just the app target) and grep for any remaining references to deleted symbols. Recorded as a durable project rule in memory (`swift_delete_needs_test_target_build.md`).

## Consequences

- All future Swift-deletion PRs must include build-for-testing verification
- Reviewers explicitly check for orphaned test files referencing deleted symbols
- PR #418 fix confirmed: grep for BlossomUploader/BlossomUploading returned ZERO, PodcastrTests compiles

## Open Tail

*(none)*

## Evidence

- transcript lines 6452-6470

