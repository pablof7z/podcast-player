---
title: D6 Null-Guard Rule for FFI Dispatch
slug: d6-null-guard-ffi
summary: FFI dispatch functions must null-guard their app pointer dereferences to degrade gracefully rather than SIGABRT. This enables unit testing of handler functions.
tags:
  - ffi
  - rust
  - testing
  - d6
  - dispatch
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# D6 Null-Guard Rule for FFI Dispatch

> FFI dispatch functions must null-guard their app pointer dereferences to degrade gracefully rather than SIGABRT. This enables unit testing of handler functions.

## D6 Rule

FFI dispatch must degrade gracefully, never crash. Fire-and-forget dispatch functions (dispatch_audio, dispatch_download, dispatch_notification) that deref app unguarded will SIGABRT on a null app pointer. This violates D6 (errors-as-data — never crash out of FFI). The publish path already null-guards its dispatch; the audio, download, and notification dispatch paths must do the same for consistency. [^14943-20]

## Null-Guard Pattern

When dispatch functions dereference app (a raw pointer to the NMP application context), the pointer may be null in test environments or during early initialization. The correct pattern wraps the deref in a guard: if app is null, return early without panicking. In production, app is never null after initialization, so the guard is purely a safety net and testability enabler. [^14943-21]

## Testability Impact

Without the null-guard, handler functions like handle_play cannot be unit-tested because constructing a PodcastHostOpHandler in a test requires a valid app pointer. The guard makes handler tests constructible with a null app, enabling proper Rust unit test coverage for migrated behaviors (e.g., enqueue-download-on-play). The publish handler already demonstrates this pattern. [^14943-22]

## See Also

