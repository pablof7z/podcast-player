---
title: Stale Rust Lib Shadowing in Linker Search Path
slug: stale-rust-lib-shadowing
summary: A stale Rust static library in the project-local target dir can shadow a freshly-built shared-target-dir lib, causing undefined symbol linker errors for newly-added FFI functions.
tags:
  - ios
  - build
  - rust
  - linker
  - troubleshooting
volatility: warm
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Stale Rust Lib Shadowing in Linker Search Path

> A stale Rust static library in the project-local target dir can shadow a freshly-built shared-target-dir lib, causing undefined symbol linker errors for newly-added FFI functions.

## Stale Local Lib Shadowing

Xcode's library search path searches $(SRCROOT)/target/aarch64-apple-ios-sim/debug before ~/.cargo/target-shared/aarch64-apple-ios-sim/debug. If a stale build of the Rust static library exists in the project-local target dir (built on a prior commit), it shadows the freshly-built shared-target-dir lib. The linker picks the stale lib and fails with undefined symbols for newly-added FFI functions. The fix: delete the stale local lib so the linker falls through to the canonical shared target dir. [^14943-27]

## Detection

When the linker reports undefined symbols for FFI functions that exist in Rust source and nm confirms they are defined (T) in the freshly-built shared-target-dir lib, the cause is a stale lib earlier in the search path. The stale lib will have an older timestamp and missing symbols. Use nm on each lib in the search path to confirm: the stale lib will show 0 instances of the new symbol; the fresh one will show exactly 1 defined instance. [^14943-28]

## See Also

