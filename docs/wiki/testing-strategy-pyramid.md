---
title: Testing Strategy Pyramid
slug: testing-strategy-pyramid
summary: "The testing strategy uses a three-layer pyramid: Layer 1 is Rust `cargo test` for kernel correctness, Layer 2 is `podcast-tui` as a headless integration harness"
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

# Testing Strategy Pyramid

## Testing Strategy Pyramid

The testing strategy uses a three-layer pyramid: Layer 1 is Rust `cargo test` for kernel correctness, Layer 2 is `podcast-tui` as a headless integration harness for bridge validation, and Layer 3 is Maestro for user journey validation to confirm the UI renders correctly. [^a6320-11]


## Layer 1: Kernel Unit Tests

Rust kernel unit tests in `apps/nmp-app-podcast` cover settings round-trips (playback rate, auto-delete, auto-skip-ads set/get/reload through disk), unsubscribe behavior (drops podcast + episodes, no-op on unknown ID), and the queue front-insertion invariant (`AddNext` on non-empty queue inserts at front). [^a6320-12]

## Layer 2: Headless Kernel Integration

A headless kernel integration binary at `apps/podcast-tui/src/bin/integration_test.rs` boots the real kernel against a live RSS feed and sequentially asserts subscribe, episodes appear, queue add, queue remove, mark played, mark unplayed, and speed setting. [^a6320-13]
## See Also

