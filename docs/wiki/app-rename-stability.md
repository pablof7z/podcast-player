---
title: App Rename Stability
slug: app-rename-stability
topic: project-setup
summary: The app display name should change from `Podcastr` to `Pod0`
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-25
updated: 2026-06-12
verified: 2026-05-25
compiled-from: conversation
sources:
  - session:rollout-2026-05-25T12-53-35-019e5e8d-dcce-7582-85bd-8c4b7d017c17
  - session:rollout-2026-05-25T12-53-46-019e5e8e-043d-7dc2-8171-2238de03d145
  - session:rollout-2026-05-25T22-18-09-019e6092-b9c8-7f53-b3e0-898bfeec48c4
---

# App Rename Stability

## Display Name Change

The product identity is renamed to Pod0 while preserving `io.f7z.podcast`, `group.com.podcastr.app`, `podcastr://`, and entitlement filenames as stable compatibility identifiers. (Previously: The app is currently configured as `Podcastr`: `Project.swift` sets `appName` and `appDisplayName` to `Podcastr`, and generated targets/schemes are `Podcastr`, `PodcastrTests`, `PodcastrWidget`, superseded — see podcast-app-state.) The app display name has been changed to Pod0 as part of the product identity rename, with `io.f7z.podcast`, `group.com.podcastr.app`, `podcastr://`, and entitlement filenames preserved as stable compatibility identifiers. (Previously: The app display name should change from `Podcastr` to `Pod0`, superseded — see podcast-app-state.) Info.plist usage strings referencing `$(PRODUCT_NAME)` should be changed to display-name-based copy or the literal `Pod0` if `appName` stays `Podcastr`.

<!-- citations: [^rollo-175] [^rollo-195] -->
## Stable Identifiers

The following identifiers must stay stable for App Store and data continuity unless intentionally creating a new app:

- Bundle IDs: `io.f7z.podcast`, `io.f7z.podcast.widget`, `io.f7z.podcast.tests`
- App Store Connect app record and provisioning identifiers
- Persistence keys and paths: `podcastr-state.v1.json`, `podcastr.state.v1`, `Application Support/podcastr/...`
- Keychain services derived from `Bundle.main.bundleIdentifier`
- The `podcastr://` URL scheme (must not be removed; `pod0` should only be added as an alias if desired)
- Spotlight domains, notification names, widget kind, background session IDs, and the NIP-73 `podcastr:clip` identifier <!-- [^rollo-176] -->

## Rename Mechanics

If the rename is display-only (`appDisplayName` → `Pod0`, `appName` stays `Podcastr`), only user-facing strings and the display name change; `@testable import Podcastr` references remain valid. If `appName` also becomes `Pod0`, every `@testable import Podcastr` must change. A full target/scheme rename requires updating `.github/workflows/testflight.yml`, `ci_scripts/run_tests.sh`, and `ci_scripts/archive_and_upload.sh` defaults from `Podcastr` to `Pod0`; a display-only rename does not. project.pbxproj is gitignored in this repo; feature PRs do not commit pbxproj regen, and the Xcode project is regenerated via `tuist generate` (run by `ci_scripts/bootstrap_project.sh`). (Previously: `Podcastr.xcodeproj/project.pbxproj` is tracked despite `*.xcodeproj/` being ignored, so a target rename requires committing generated project changes and likely `git add -f` for a new `Pod0.xcodeproj`. <!--  -->, superseded — see tuist-project-configuration.)

## Stale PRs

PR #2 is a stale Swift-only Pod0/NIP-F4 rename that should be closed because the NIP-F4 intent was already applied to the old codebase. <!-- [^rollo-205] -->
