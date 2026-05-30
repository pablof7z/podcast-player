---
title: NMP Version Upgrades
slug: nmp-version-upgrades
summary: "Process for upgrading NMP versions: pin bump, three-layer verification, changelog, and stable base commit."
tags:
  - nmp
  - upgrade
  - version
  - cargo
  - verification
volatility: warm
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# NMP Version Upgrades

> Process for upgrading NMP versions: pin bump, three-layer verification, changelog, and stable base commit.

## Pin Management

NMP is consumed via a git revision pin in `Cargo.toml`. The four pins (for nmp-core, nmp-ffi, and their dependencies in the podcast crate) must all point at the same commit. To upgrade, bump all pins to the new revision (or tag), regenerate `Cargo.lock`, and run `cargo check --workspace` for the host target to surface compile-time breakages. [^14943-51]

## Three-Layer Verification

`cargo check --workspace` on the host target is insufficient to prove an upgrade is clean. The minimum verification is three layers:
1. Host `cargo check --workspace` — compile-time Rust breakages
2. iOS simulator static lib build: `cargo build -p nmp-app-podcast --target aarch64-apple-ios-sim`
3. iOS app build via Xcode (must link against the freshly-rebuilt lib)

All three layers must succeed before the upgrade is considered verified. A live boot smoke-test (launch, confirm kernel initializes, library projects) adds confidence. [^14943-52]

## Commit and Test

The upgrade pin bump is committed on `main` before any adoption work begins. This provides a stable base commit for worktree branches. The smoke test should confirm the app launches, the kernel initializes without panics, no `store_open_failure` fires spuriously, and logs show no FFI errors. A fresh simulator device may be needed if the existing device is corrupted. [^14943-53]

## Changelog Generation

When upgrading NMP, a changelog must be produced summarizing everything new between the old and new pins. This includes:
- New mandatory features (e.g., `store_open_failure`)
- New optional capabilities (e.g., `active_account_handle`)
- New infrastructure (e.g., typed FlatBuffers sidecar for ADR-0037)
- Any breaking changes to the FFI surface or generated types

The changelog is written to `docs/plan/nmp-v0.1.0-upgrade.md` and referenced from `docs/plan.md`. [^14943-54]

## See Also
- [[nmp-integration-rules|NMP Integration Rules]] — related guide
- [[ios-build-pipeline|iOS Build Pipeline]] — related guide

