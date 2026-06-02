---
title: Known Bug Patterns
slug: known-bug-patterns
summary: "Recurring bug patterns: observation race conditions, Rust binary staleness, ABI mismatches, schema mirror drift, and silent decode failures."
tags:
  - bugs
  - patterns
  - race-condition
  - abi
  - schema
  - decode
volatility: warm
confidence: medium
created: 2026-05-29
updated: 2026-05-30
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Known Bug Patterns

> Recurring bug patterns: observation race conditions, Rust binary staleness, ABI mismatches, schema mirror drift, and silent decode failures.

## withObservationTracking Race Condition

When `kernel.library` is already set to its final value before the `kernelObservationTask` starts, `withObservationTracking` arms on an already-final value. Since the value never changes again, `onChange` never fires, and `applyKernelState` is never called. The fix: restructure the loop to call `applyKernelState` at the TOP of each iteration (before `await`), then arm the observation, then wait. The task's first iteration always applies the current library state regardless of timing. <!-- [^14943-55] -->

## Streaming URL from Rust Projection

The `EpisodeSummary` must include `enclosure_url: Option<String>` projected from Rust's `Episode.enclosure_url`. The Swift `toEpisode` function uses this as the streaming URL when `downloadPath` is absent: `enclosureUrl.flatMap { URL(string: $0) }` as fallback before the placeholder. Without this, AVPlayer tries to play from `https://placeholder.invalid/{id}` and fails silently. <!-- [^14943-56] -->

## Rust Binary Staleness

Xcode does not detect changes in the Rust static library. After modifying Rust source, the iOS simulator static lib must be rebuilt manually. If the app launches but Rust changes appear not to take effect (e.g., position stuck at 0:00 despite an `enclosure_url` fix), the binary timestamp should be checked: the Rust lib in `~/.cargo/target-shared/aarch64-apple-ios-sim/debug/` may be hours older than the source changes. <!-- [^14943-57] -->


A stale build of the Rust static library in the project-local target dir ($(SRCROOT)/target/aarch64-apple-ios-sim/debug) can shadow a freshly-built shared-target-dir lib. The linker search path searches the project-local dir first. If the stale lib was built on a prior commit, it lacks newly-added FFI symbols. The fix is to delete the stale local lib so the linker falls through to the canonical shared target dir. This is detected when nm confirms a symbol is defined (T) in the fresh lib but the linker still reports it as undefined. <!-- [^14943-40] -->
## Push Callback Not Firing at Startup

On a bare (no-identity) launch, the generic kernel push callback may not deliver a usable frame — the podcast projection was never registered through the canonical seam, so the push carries nothing. This is an app-shell wiring bug, not an NMP limitation. The fix is to register the projection through `nmp_app_register_snapshot_projection` and ensure the `listen()` callback is subscribed before `start()` is called. <!-- [^14943-58] -->

## FlatBuffers ABI Mismatch

The kernel delivers binary FlatBuffers frames `(ptr, len)` via the update callback, but the hand-maintained `NmpCore.h` header declared a JSON `const char*` callback. The Swift `String(cString:)` call stopped at the first NUL byte in the binary buffer, producing 1-byte reads. This is not caught by `cargo check` or Xcode build — it's a runtime ABI mismatch at the Swift/C boundary. Every push frame silently failed to decode. <!-- [^14943-59] -->

## D5 Schema Mirror Drift

Rust projection types use `skip_serializing_if` (D5 wire contract) but the hand-maintained Swift mirror types non-optionally correspond to fields that Rust omits. Swift's synthesized `Codable` ignores property defaults for absent keys, so real-feed data triggers `keyNotFound` on `autoDownload`, `played`, `starred`, and all empty collections. The `try?` in the pull decode path hid these failures — empty-state frames appeared to work while any frame with real podcast data failed silently. <!-- [^14943-60] -->


Four playback regressions were found by codex in the M1 stack: (1) Replay of a completed episode resumes at the end because Rust's ItemEnd writeback leaves position at duration — fix by resetting position to 0 on natural completion. (2) markEpisodePlayed ignores the autoMarkPlayedAtEnd setting — fix by gating on the setting. (3) Segment boundaries set before setEpisode cause bounded clips to play past their end — fix by setting currentSegmentEndTime after setEpisode. (4) setEpisode calls kernelDownload unconditionally, triggering redundant downloads — fix by gating on .notDownloaded or .failed. <!-- [^14943-41] -->
## Missing Voice Report Channel

When the poll was replaced with event-driven `onSnapshotMaybeChanged` hooks, the `attachVoiceReportChannel` was initially not wired. This caused voice state (listening/transcript/speaking) to go stale. All three report channels (audio, download, voice) must fire the reactive pull hook. <!-- [^14943-61] -->


When wifi_only gating is active, episodes seen during a cellular feed refresh are added to existing_guids, preventing them from ever being auto-downloaded on subsequent Wi-Fi refreshes. The episodes are permanently discarded rather than deferred for later download when connectivity changes. This needs deferred-download tracking (a queue of episodes seen on cellular that should be re-evaluated when Wi-Fi connects). This is a tracked backlog item. <!-- [^14943-74] -->
## See Also
- [[nmp-update-transport|NMP Update Transport (FlatBuffers Push)]] — related guide
- [[d5-wire-contract|D5 Wire Contract and Swift Decode Resilience]] — related guide
- [[kernel-bridge-patterns|Kernel Bridge Patterns]] — related guide
- [[nmp-v0-1-0-adoption|NMP v0.1.0 Adoption]] — related guide
- [[playback-engine-m1-part3|Playback Engine (M1 Part 3 Engine Swap)]] — related guide

