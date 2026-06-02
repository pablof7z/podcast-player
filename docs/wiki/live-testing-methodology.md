---
title: Live Testing Methodology
slug: live-testing-methodology
summary: "Methodology for live testing via Xcode MCP: verification requirements, simulator management, debug logging, and throwaway edit protocol."
tags:
  - testing
  - simulator
  - verification
  - xcode-mcp
  - debug
volatility: warm
confidence: medium
created: 2026-05-29
updated: 2026-05-30
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Live Testing Methodology

> Methodology for live testing via Xcode MCP: verification requirements, simulator management, debug logging, and throwaway edit protocol.

## Live Verification Requirements

Every change that touches the data path must be verified live on the simulator via Xcode MCP. The verification must include:
- Launch smoke test: app boots, kernel initializes without panics, no FFI errors in logs
- Library rendering: subscribed podcasts appear with episodes, artwork, titles, and timestamps
- Subscribe flow: subscribing to a real feed populates the library (must test with a real, large feed like The Daily with 2615 episodes)
- Decode verification: zero `keyNotFound` or decode errors in logs
- Push transport: push frames decode correctly (no 1-byte reads, no envelope decode errors)
- Reactive updates: host-op changes propagate without polling (e.g., inbox picks count updating) <!-- [^14943-70] -->

## Debug Logging

Temporary debug logs are used during investigation but must be removed before committing. Debug logs in the kernel bridge should use `NSLog` or `os_log`. The unified log can be captured via `simctl ... log show`. However, log capture in the simulator is unreliable — `NSLog` output may not appear in the captured stream depending on the log level and capture method. When logs are unreliable, use UI-based verification (screenshots) as the primary evidence. <!-- [^14943-71] -->

## Simulator Management

The simulator (iPhone 17 Pro, iOS 26.4, Bundle `io.f7z.podcast`) can become unstable. The CoreSimulator daemon may crash or flap. Recovery steps:
1. Kill CoreSimulator: `sudo killall -9 SimLaunchd 2>/dev/null; killall -9 -m CoreSimulator 2>/dev/null`
2. Wait for the daemon to restart and re-index devices
3. If the device vanishes from the list, create a fresh one: `xcrun simctl create ...`
4. The device UUID changes on recreation; update all references

If the data volume fills up (100% usage), builds and codex reviews will fail with `ENOSPC`. The primary space hogs are `~/.cargo/target-shared` (83 GB iOS build cache) and stale `Podcastr-*` DerivedData directories. <!-- [^14943-72] -->


When the data volume fills up (100%), the primary space hogs are ~/.cargo/target-shared (~83 GB iOS build cache) and stale DerivedData directories (~9 Podcastr-* dirs, ~7 GB total). After reclaiming space (90 GB freed), the iOS simulator static library must be rebuilt from scratch since it was stored in the cleared cache directory. The codex review gate detects ENOSPC as an exit-101 error. <!-- [^14943-77] -->
## Worktree vs Main Repo

Worktrees build into a different DerivedData folder than the main repo (e.g., `Podcastr-geippxazsjqayvewadgcfamxyzxd` vs `Podcastr-fwhkqpldihbsdifvxhjkgpvbypfl`). When installing a build from a worktree, always use the worktree's DerivedData product path. Installing the main repo's binary while testing worktree changes produces false results (the stale main build runs instead). <!-- [^14943-73] -->


After a merge, the rebuilt app must be installed and visually verified. The first screenshot may race the initial render — if it appears blank, wait a moment and re-capture. The UI hierarchy (via describe_ui) is a more reliable initial check than a screenshot for confirming the app booted correctly. <!-- [^14943-42] -->
## Throwaway Edits for Verification

For UI verification that requires forcing a condition (e.g., forcing `storeOpenFailure` to a non-nil value to confirm the alert renders), use throwaway edits with the following protocol:
1. Make the minimal edit to trigger the condition
2. Build and install the correct binary (confirm DerivedData path)
3. Screenshot to verify the UI
4. Revert every throwaway edit precisely
5. Verify no throwaway residue remains in `git diff`
This ensures the production code is verified without committing test-only changes. <!-- [^14943-74] -->

## See Also
- [[codex-review-gate|Codex Review Gate]] — related guide
- [[ios-build-pipeline|iOS Build Pipeline]] — related guide

