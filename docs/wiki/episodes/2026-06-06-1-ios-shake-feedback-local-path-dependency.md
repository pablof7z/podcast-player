---
type: episode-card
date: 2026-06-06
session: 52b667b5-ed45-479e-a960-1baeefbbdf03
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/52b667b5-ed45-479e-a960-1baeefbbdf03.jsonl
salience: architecture
status: active
subjects:
  - ios-shake-feedback
  - dependency-management
  - swift-package-manager
supersedes: []
related_claims: []
source_lines:
  - 1-251
captured_at: 2026-06-12T13:24:17Z
---

# Episode: ios-shake-feedback: local path dependency → published remote

## Prior State

ios-shake-feedback was referenced as a local path dependency (.local(path: "../ios-shake-feedback")), meaning the podcast-player project could only be built on machines with the ios-shake-feedback repo cloned as a sibling directory.

## Trigger

User identified that the relative-path dependency prevented the project from being built on other computers and asked to fix it.

## Decision

Published ios-shake-feedback to GitHub (pablof7z/ios-shake-feedback, tagged 1.0.0) and switched Project.swift from .local(path:) to .remote(url:requirement:) with .upToNextMajor(from: "1.0.0").

## Consequences

- The podcast-player project is now buildable on any machine without requiring a sibling checkout of ios-shake-feedback.
- The 48MB ShakeFeedbackCore.xcframework binary is committed in the GitHub repo, making clones large — flagged as a future concern.
- Version semantics now apply: downstream consumers will resolve ios-shake-feedback via semver ranges rather than implicit local filesystem state.

## Open Tail

- The 48MB xcframework in git should ideally move to a .binaryTarget(url:checksum:) served via GitHub Releases for leaner clones.

## Evidence

- transcript lines 1-251

