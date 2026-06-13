---
title: Testing Strategy
slug: testing-strategy
topic: testing-strategy
summary: Test scenarios for the app are maintained in test-scenarios.json and include 49 scenarios covering P0 core journeys, P1 important features, and P2 edge cases, e
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-02
updated: 2026-06-13
verified: 2026-06-02
compiled-from: conversation
sources:
  - session:a6320d4d-f2c8-4a8b-a21a-d71f5af73509
  - session:b4d663c7-85f0-4086-9bdc-030177ef43e5
  - session:c33b9adb-9d1a-4717-9314-b45a61e6cbc3
  - session:rollout-2026-05-25T22-18-09-019e6092-b9c8-7f53-b3e0-898bfeec48c4
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Testing Strategy

## Test Scenarios

A 50-scenario test plan (10 P0) is documented in docs/plan/qa-scenario-tests.md, with scenarios covering P0 core journeys, P1 important features, and P2 edge cases, each with preconditions, ordered steps, assertions, and performance budgets.

<!-- citations: [^a6320-4] [^b4d66-3] -->
## Test Layers

The podcast-tui codebase has diverged and no longer compiles (≥8 compilation errors including a nonexistent method and unhandled enum variant), so it cannot currently serve as a headless integration harness for bridge validation. (Previously: Testing strategy is structured as a three-layer pyramid: Rust cargo tests for kernel correctness, podcast-tui as a headless integration harness for bridge validation, and Maestro for simulator UI journey validation, superseded — see podcast-tui.) Physical-device UI automation on iOS 26.6 uses XCUITest via xcodebuild (CoreDevice channel), because idb is too old (2022), maestro's device-tunnel is broken (simulator-only), and MCP tap/describe_ui/screenshot tools are simulator-only. The XCUITest harness is black-box: PodcastrUITests uses XCUIApplication(bundleIdentifier:) to drive the installed app by bundle ID without linking the app or its Rust kernel, so xcodebuild test builds only the tiny test runner. The device must have Settings → Developer → Enable UI Automation set to ON, or XCUITest and all other automation frameworks time out with 'Timed out while enabling automation mode'. When Maestro needs to assert kernel-level state (e.g., bytes written, Nostr event relayed), the mechanism is to surface that data into the accessibility tree via a debug JSON dump view with a stable accessibility ID. Maestro background and offline scenarios are marked with a MANUAL VERIFICATION REQUIRED comment rather than fully automated assertions. Physical-device-only scenarios (real-hardware perf, lock screen, CarPlay, Live Activity, handoff) are blocked and should be marked as such rather than faked. The playback substate migration (step 14) has rewired player_actor, queue, and download_queue into state.playback with unchanged lock topology, so those kernel files are no longer under active peer rewriting. (Previously: Kernel playback/position/CPU files (audio_report.rs, player_actions.rs, store playback) must not be edited by the QA agent because peers own them and are actively rewriting them, superseded — see podcast-app-state.) The simulator is shared with other agents who may overwrite the installed build; the QA agent must reinstall its own build before each UI verification to avoid 'Application failed preflight checks / Busy' errors. Focused xcodebuild test runs for the touched test bundles are preferred during development; full-suite simulator validation is the merge/supervisor gate unless the change is broad enough to require it earlier.

<!-- citations: [^a6320-5] [^a6320-6] [^a6320-7] [^b4d66-4] [^rollo-213] -->
## Accessibility Identifiers

18 accessibilityIdentifier values are added to the live iOS shell for tabs, mini-player, player controls, episode rows, search, library, downloads, and settings. Maestro flows require the a11y ID PR (#235) to be merged before they can reference identifiers in the simulator. The PodcastrUITests target and scheme are added to Project.swift, with test sources in AppUITests/Sources/{UITestSupport,SmokeUITests,CoreJourneyUITests,SurveyUITests}.swift.

<!-- citations: [^a6320-8] [^b4d66-5] -->
## Maestro Flows

P0 Maestro flows are organized under tests/maestro/ with 8 flow files, a shared launch.yaml, a subscribe-darknet.yaml helper, config.yaml, and README.md, run via `maestro test tests/maestro/config.yaml`. <!-- [^a6320-9] -->

## Merge Order

The recommended merge order for the four testing PRs is: #234 (Rust kernel tests) first, then #235 (a11y IDs), then #232 (integration binary), then #233 (Maestro flows). <!-- [^a6320-10] -->

## Verified Scenarios

Cold launch performance on device averages 1.389s (RSD 1.6%), within the <2.0s P0-01 budget. P0-03 (play starts real audio) passes: Pause appears within 3s and timecode advances over 4s, proving actual audio playback. In-session position tracking works: Library → In Progress lists the played episode, and the mini-player shows the saved position (e.g., 0:10) after pausing. Search, Library, Wiki, Bookmarks (proper empty state with 'No Bookmarks Yet' + guidance), and sidebar navigation all pass on device. <!-- [^b4d66-6] -->


Android Tier-2 is fully shipped: Inbox, Transcripts, Agent chat (#408), AI picks/categories rail (#410), AI chapters + auto-skip ads (#416). <!-- [^c1691-217] -->
## Unverified / Blocked Scenarios

The Resume-on-reopen label (showing 'Resume' with saved timecode in episode detail after cold relaunch) is unconfirmed, not a verified defect — all prior P0-04 reopen tests were confounded by stale detail bindings, feed reordering, and black-box plumbing fragility. The pre-existing PodcastrTests compile regression (opml_roundtrip.rs referencing the deleted PodcastKind) has been fixed. (Previously: A pre-existing PodcastrTests compile regression exists and is logged in BACKLOG as P0, superseded — see podcast-subscription-flow.) Survey tests 03–05 (Agent chat, Settings → Models/Local + Debug, Download live-progress) failed only due to device contention from concurrent peer agents, not due to app defects, and need to be re-run. A physical iPhone is now available for on-device testing, with an XCUITest driving the real Agent UI and an on-device Gemma model responding to messages. (Previously: The continuing agent has no physical device and no on-device models; all testing must use the simulator (iPhone 16 ci, UUID 000B3DA4-5A93-41F6-BA88-12665CF29867) and AI/LLM scenarios must use Ollama (localhost:11434, deepseek-v4-flash:cloud / deepseek-v4-pro:cloud) configured via Settings → Models, superseded — see pablo-iphone-build.)

<!-- citations: [^b4d66-7] [^c33b9-9] -->
## QA Worktree

The QA worktree is at /Users/pablofernandez/Work/podcast-player-qa on branch qa/device-scenario-tests (PR #268), with the Rust kernel already built for both aarch64-apple-ios and aarch64-apple-ios-sim. <!-- [^b4d66-8] -->
