---
title: NMP Update Transport (FlatBuffers Push)
slug: nmp-update-transport
summary: The kernel delivers updates as binary FlatBuffers frames via a (ptr, len) callback, decoded through a Rust helper into JSON for Swift consumption.
tags:
  - nmp
  - transport
  - flatbuffers
  - ffi
  - push
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# NMP Update Transport (FlatBuffers Push)

> The kernel delivers updates as binary FlatBuffers frames via a (ptr, len) callback, decoded through a Rust helper into JSON for Swift consumption.

## Transport Mechanism

The kernel's update callback delivers a binary FlatBuffers frame, not a NUL-terminated JSON string. The Rust FFI signature is `extern "C" fn(*mut c_void, *const u8, usize)` — context, bytes, and length. The Swift side receives `(UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int)` and must decode the length-delimited binary frame, not call `String(cString:)`. <!-- [^14943-1] -->

## C Header Declaration

`NmpCore.h` declares the callback as:
```c
typedef void (*NmpUpdateCallback)(void *context, const uint8_t *bytes, size_t len);
```
The header must include `<stddef.h>` for `size_t`. This declaration must stay in sync with the Rust symbol to satisfy the `ci/check-ffi-header-drift.sh` gate. <!-- [^14943-2] -->

## Rust Decode Helper

A `nmp_app_podcast_decode_update_frame(bytes: *const u8, len: usize) -> *mut c_char` FFI symbol decodes the binary FlatBuffers frame via `nmp_core::decode_update_frame`. It returns a JSON envelope string:
- `{"t":"snapshot","v":<value>}` for successful snapshots
- `{"t":"panic","message":"..."}` for panic frames

The caller owns the returned string and must free it via `nmp_app_free_string`. <!-- [^14943-3] -->

## Swift Callback Implementation

The Swift `nmpUpdateCallback` is a `@convention(c)` closure matching the `(ptr, len)` signature. It:
1. Receives bytes + length from the kernel
2. Calls `nmp_app_podcast_decode_update_frame(bytes, len)` to get JSON
3. Converts the C string to `String`, then frees it via `nmp_app_free_string`
4. Deserializes the envelope via `JSONDecoder` using a `SnapshotEnvelope` type with a `let t: String` discriminator
5. Routes `t == "snapshot"` frames through the existing decode path <!-- [^14943-4] -->

## Projection Extraction

When the envelope type is `"snapshot"`, the `v` payload's `projections["podcast.snapshot"]` key is extracted and decoded as a `PodcastUpdate`. This is how the podcast projection rides the reactive push frame. A `decodePodcastUpdate(envelopePayload:)` helper on `PodcastHandle` performs this extraction and JSON-to-`PodcastUpdate` decoding. <!-- [^14943-5] -->

## Historical ABI Mismatch

Prior to the v0.1.0 adoption, `NmpCore.h` declared the callback as `typedef void (*NmpUpdateCallback)(void *context, const char *json)` — a JSON C-string. This mismatch existed since NMP commit `021ba295` introduced binary FlatBuffers frames. The Swift side called `String(cString: pointer)`, which stopped at the first NUL byte in the binary buffer, producing 1-byte reads that always failed to decode. This is why the reactive push never worked in the original shell, and why the bespoke pull symbol + 500ms poll were originally bolted on. <!-- [^14943-6] -->

## See Also
- [[podcast-projection-registration|Podcast Projection Registration]] — related guide
- [[d5-wire-contract|D5 Wire Contract and Swift Decode Resilience]] — related guide
- [[known-bug-patterns|Known Bug Patterns]] — related guide
- [[store-open-failure-alert|Store Open Failure Alert]] — related guide

