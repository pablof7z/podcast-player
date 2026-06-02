---
title: "Test Migration: Swift → Rust Coverage"
slug: test-migration-pattern
summary: When Swift behavior migrates to Rust, Swift tests are deleted only after confirming equivalent Rust coverage exists. Coverage audit and handler test construction patterns.
tags:
  - testing
  - rust
  - swift
  - migration
  - coverage
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Test Migration: Swift → Rust Coverage

> When Swift behavior migrates to Rust, Swift tests are deleted only after confirming equivalent Rust coverage exists. Coverage audit and handler test construction patterns.

## Migration Principle

When Swift behavior is migrated to Rust, the corresponding Swift tests must be deleted — but only after confirming equivalent Rust test coverage exists. Deleting Swift tests without Rust coverage is a net loss of behavioral verification. The codex review gate enforces this: it expects that deleted test suites have their coverage preserved in the target implementation language. <!-- [^14943-23] -->

## Coverage Audit Pattern

The audit pattern for each deleted Swift test: (1) identify what behavior the Swift test verified, (2) confirm the Rust migration implements that behavior (read the handler source), (3) check whether a dedicated Rust test exists for that specific behavior path, (4) if no Rust test exists, add one before deleting the Swift test. The publish handler demonstrates the construction pattern for unit-testable handlers (handler_with_store helper). <!-- [^14943-24] -->

## M1.5 Deleted Callbacks

#133's M1.5 migration deleted three PlaybackState callback categories, with behavior moved to Rust: onPersistPosition/onFlushPositions — position now Rust-owned via audio reports (covered by playing_report_writes_position_back_to_store and delta-flush tests); onEnsureDownloadEnqueued — now Rust handle_play enqueues download on play (had no Rust test, so one was added in player_actions_tests.rs); playNext auto-advance — now Rust maybe_auto_advance (tested in audio_report.rs). PlaybackState.playNext still exists and its test was preserved. <!-- [^14943-25] -->

## Test Construction Pattern

Rust handler tests use the handler_with_store pattern from host_op_publish_tests.rs. A PodcastHostOpHandler is constructed with a null app pointer (safe after D6 guards), a fresh Store, and a fresh DownloadQueue. The test constructs the handler, calls the function under test, then asserts on store state or download queue contents. Example assertion: store.episodes.get(&ep_id) confirms the episode was persisted; DownloadQueue::get confirms enqueue. <!-- [^14943-26] -->
