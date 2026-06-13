---
title: Swift Package Dependencies
slug: swift-package-dependencies
topic: project-setup
summary: Podcastr and the local `ios-shake-feedback` dependency must reference the same `secp256k1` package identity to keep the SwiftPM dependency graph resolvable
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-17
updated: 2026-06-12
verified: 2026-05-17
compiled-from: conversation
sources:
  - session:rollout-2026-05-17T10-33-06-019e34da-5c83-7591-8bfc-850541168727
  - session:rollout-2026-05-25T12-53-46-019e5e8e-043d-7dc2-8171-2238de03d145
  - session:rollout-2026-06-10T23-25-38-019eb336-424e-7cf2-a351-7654f7a0b9af
---

# Swift Package Dependencies

## Dependency Resolution

The ios-shake-feedback dependency is referenced as a remote package from https://github.com/pablof7z/ios-shake-feedback with .upToNextMajor(from: "1.0.0"), so a local sibling checkout is no longer required for Tuist generation and builds. (Previously: The local package dependency `../ios-shake-feedback` must exist for Tuist generation and builds, superseded — see nmp-version-upgrades.) ios-shake-feedback's Package.swift was switched from 21-DOT-DEV/swift-secp256k1 to GigaBitcoin/recp256k1.swift (importing P256K) to resolve a pre-existing duplicate-symbol conflict, changing the secp256k1 package identity that must be shared. (Previously: Podcastr and the local `ios-shake-feedback` dependency must reference the same `secp256k1` package identity to keep the SwiftPM dependency graph resolvable, superseded — see pablo-iphone-build.) ios-shake-feedback imports P256K from GigaBitcoin/recp256k1.swift, not from the resolved swift-secp256k1 version. (Previously: The local `ios-shake-feedback` package must import the `P256K` product/module exposed by the resolved `swift-secp256k1` version rather than a missing module name, superseded — see pablo-iphone-build.) The secp256k1.swift package (version ≥ 0.23.2) ships a SharedSourcesPlugin BuildToolPlugin that requires the `-skipPackagePluginValidation` flag on every xcodebuild invocation in CI scripts and on any MCP build_sim / build_device call via extraArgs, or the build will fail.

<!-- citations: [^rollo-156] [^rollo-200] [^rollo-267] -->
