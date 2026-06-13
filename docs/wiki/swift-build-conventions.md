---
title: Swift Build Conventions
slug: swift-build-conventions
topic: project-setup
summary: When deleting Swift files, running `xcodebuild build-for-testing` (the PodcastrTests target, not just the app target) is required to catch orphaned references,
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-12
updated: 2026-06-13
verified: 2026-06-12
compiled-from: conversation
sources:
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Swift Build Conventions

## Deleting Swift Files

When deleting Swift files, running `xcodebuild build-for-testing` (the PodcastrTests target, not just the app target) is required to catch orphaned references, because Rust-only and app-only builds mask Swift compile breaks. The test target globs `AppTests/Sources/**` and compiles files that reference deleted production code. This orphaned-overrides trap caught both `AIChapterCompiler.swift`'s `overlapsAd` extension (#413) and `BlossomUploaderTests.swift` (#418), which were masked by app-only or Rust-only builds.

KernelSigner struct, NostrSigner protocol, and NostrEventDraft are deleted as dead code (zero callers post-Blossom migration), while NostrSignerError is retained because it is still used by KernelBridge.swift and SignedEventsRegistryTests.swift. <!-- [^c1691-216] -->

<!-- citations: [^c1691-173] [^c1691-188] [^c1691-200] [^c1691-215] -->
