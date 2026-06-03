---
title: Maestro E2E Testing
slug: maestro-e2e-testing
summary: Test scenarios for the app are generated and stored in `test-scenarios.json`, organized by priority (P0 for core journeys, P1 for important features, P2 for edg
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:a6320d4d-f2c8-4a8b-a21a-d71f5af73509
---

# Maestro E2E Testing

## Test Scenario Definitions

Test scenarios for the app are generated and stored in `test-scenarios.json`, organized by priority (P0 for core journeys, P1 for important features, P2 for edge cases) and area. Each test scenario includes `preconditions`, ordered `steps` written as simulator interactions, `assertions`, and a `performance_budget` where applicable. [^a6320-3]


Background and offline scenarios in the Maestro flow suite are marked with `# MANUAL VERIFICATION REQUIRED`. [^a6320-4]

## Maestro vs XCUITest

Maestro flow specs can run on both iOS and Android platforms, whereas XCUITest is iOS-only but provides `launchEnvironment`/`launchArguments` for seeding state without network dependency. [^a6320-5]

## Cross-Process State Verification

Maestro runs in a separate process and cannot inspect in-process state like `KernelModel.shared` directly. When a kernel assert is needed from a Maestro test (e.g. verifying bytes written or a Nostr event hitting a relay), the data must be surfaced into the accessibility tree via a debug JSON dump view with a stable accessibility ID. [^a6320-6]

## Accessibility Identifiers

The iOS shell must have stable `accessibilityIdentifier` values on tab bar items, subscribe/unsubscribe buttons, play/pause/skip controls, episode row cells, download buttons/progress indicators, and search fields/result rows before Maestro tests can reliably target them. 18 `accessibilityIdentifier` values are added to the live iOS shell for tabs, mini-player, player controls, episode rows, search, library, downloads, and settings. [^a6320-7]

## Flow Structure and Navigation

P0 Maestro flows are stored under `tests/maestro/` with a shared `launch.yaml`, a `subscribe-darknet.yaml` helper, 8 P0 flow files, `config.yaml`, and `README.md`. Maestro flows use the real navigation structure: sidebar → Add Show → Discover for subscribe, long-press context menu for queue, and `tabViewBottomAccessory` mini-player for playback. [^a6320-8]

## Running the Test Suite

The Maestro test suite is run via the command `maestro test tests/maestro/config.yaml`. [^a6320-9]

## Merge Dependencies

PR #235 (a11y IDs) must be merged before PR #233 (Maestro flows) so the simulator has the identifiers the flows reference. [^a6320-10]
## See Also

