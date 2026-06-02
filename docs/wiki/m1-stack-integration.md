---
title: M1 Stack Integration (PRs #132/#133 onto Reactive Bridge)
slug: m1-stack-integration
summary: "Integrating the stale M1 Part 3 PR stack (#132/#133) onto the post-NMP-v0.1.0 reactive bridge: merge conflict resolution, bridge collision patterns, and validated integration steps."
tags:
  - m1
  - playback
  - bridge
  - merge
  - integration
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-30
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# M1 Stack Integration (PRs #132/#133 onto Reactive Bridge)

> Integrating the stale M1 Part 3 PR stack (#132/#133) onto the post-NMP-v0.1.0 reactive bridge: merge conflict resolution, bridge collision patterns, and validated integration steps.

## PR Stack Relationship

The M1 Part 3 work arrived as two stacked PRs: #132 (feat: M1.4+M1.5 — widget writes to kernel projection path, delete PlaybackState business callbacks) and #133 (feat: M1/Part3 — AudioEngine → AudioCapability kernel bridge, PlaybackState becomes a pure renderer). #133 contains #132; they form a stack. Integrating #133 lands both. Together they finish most of Milestone M1 from migration-v2.md. <!-- [^14943-15] -->

## Merge Conflict Surface

The full M1 stack merged against the post-NMP-v0.1.0 reactive bridge (#136) produces three textual conflicts: `whats-new.json` (trivial — keep both entries), `KernelModel.swift` (the reactive apply() region), and `KernelBridge+Callbacks.swift` (the audio report threading). Other bridge/capability files #133 touches do not textually conflict but carry semantic risk against the new reactive bridge. Since #133 contains #132, merging #133 lands both. <!-- [^14943-16] -->

## Reactive vs Poll Bridge Collision

The core merge collision is between #133's M1 audio-report model (background-queue FFI call to prevent SyncCapabilityBridge deadlock) and #136's reactive model (MainActor.assumeIsolated for the audio report callback). The correct resolution combines both: #133's background-queue FFI call prevents the deadlock when Rust's maybe_auto_advance re-enters SyncCapabilityBridge and calls DispatchQueue.main.sync; #136's reactive onSnapshotMaybeChanged hook is hopped back to main via Task { @MainActor in ... } after the background FFI completes. AudioCapability is @MainActor and fires sendReport from main, so the combined approach is consistent with the already-merged download/voice channels. <!-- [^14943-17] -->

## Stale Comment Cleanup

After integration, stale comments in capabilities added by #133 may reference the deleted startSnapshotPoll. These must be cleaned up before the codex gate. The affected files include iCloudSyncCapability, SpotlightCapability, and LiveActivityManager. Although applyPodcastUpdate (the reactive path) drives all platform capabilities reactively, the stale poll-referencing comments would draw a codex flag. <!-- [^14943-18] -->

## Integration Validation Sequence

The validation sequence for the integrated M1 stack is: (1) Rust cargo test -p nmp-app-podcast --lib — must pass all D5 contract tests (702+); (2) iOS app build via Xcode against the rebuilt sim lib; (3) live smoke test — library/inbox/picks render reactively, playback works (tap hero pick → mini-player tracks position, picks count updates via push); (4) focused Swift tests; (5) code review via Opus agent. After the Rust iOS sim lib was rebuilt and the stale local lib shadowing the fresh build was removed, the integration built clean and passed live verification. <!-- [^14943-19] -->


The full validation sequence for the converged M1 stack was: (1) Rust 706 tests pass after all fixes, (2) iOS app builds clean against the rebuilt sim lib, (3) live smoke test confirmed library/inbox/picks render reactively with playback tracking position across sessions (0:06→1:28), (4) codex exec review --base main went through 4 passes — pass 1 found 4 playback regressions (fixed), pass 2 found the dual-queue P1 + 3 other findings (fixed), pass 3 found 4 localized logic nits (fixed), and pass 4 returned clean with "No actionable correctness issues." The final PR #138 was merged to main. <!-- [^14943-73] -->
