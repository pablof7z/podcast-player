---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - swift-build-process
  - overlapsAd-orphan
supersedes: []
related_claims: []
source_lines:
  - 5836-5903
captured_at: 2026-06-12T21:53:41Z
---

# Episode: Delete-Swift PRs must run real xcodebuild — not just cargo test

## Prior State

PRs that delete or move Swift code were validated with cargo test (Rust-only test suite); passing Rust tests was treated as sufficient verification

## Trigger

#413 review caught that deleting AIChapterCompiler.swift also deleted the overlapsAd extension (Episode.Chapter.overlapsAd), which was still called by production Swift code (PlayerChaptersScrollView.swift:67) and test code (AdSegmentDetectorTests.swift). All 1,229 Rust tests passed — the orphaned reference was Swift-only and invisible to cargo test.

## Decision

All PRs that delete or move Swift files must run a real xcodebuild compile (not just cargo test). Baked into future implementer prompts.

## Consequences

- The overlapsAd extension was relocated verbatim to Episode+AdOverlap.swift — one definition, zero compile errors after xcodebuild
- Process doctrine: the implementer for the Blossom deletion (which also deletes a Swift file) has this flagged
- Tuist-generated projects need tuist generate before xcodebuild sees newly-globbed source files

## Open Tail

*(none)*

## Evidence

- transcript lines 5836-5903

