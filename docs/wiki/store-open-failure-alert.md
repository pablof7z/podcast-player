---
title: Store Open Failure Alert
slug: store-open-failure-alert
summary: When the LMDB store fails to open, the kernel surfaces a store_open_failure diagnostic via the push frame, which the app must present as a user-facing alert.
tags:
  - nmp
  - store
  - lmdb
  - error-handling
  - alert
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Store Open Failure Alert

> When the LMDB store fails to open, the kernel surfaces a store_open_failure diagnostic via the push frame, which the app must present as a user-facing alert.

## Mandatory Surface Requirement

NMP v0.1.0 includes a `store_open_failure` diagnostic field in the generic `KernelUpdate` (the push snapshot frame). The host MUST surface this to the user when LMDB fails to open. It is a top-level field in the pushed envelope value, not inside `projections["podcast.snapshot"]`. [^14943-17]

## Extraction

A `extractStoreOpenFailure(envelopePayload:)` helper reads `store_open_failure` from the raw envelope value (the `v` payload, not the projection). It returns `String?`. The field is assigned in `KernelModel.apply(result:)` BEFORE the `update.rev > rev` guard, because a store-open failure can arrive on the very first frame (rev may not advance the guard, but the health flag must be honored regardless). The `KernelUpdateResult` struct carries `storeOpenFailure: String?`. [^14943-18]

## Alert Presentation

A `StoreFailureAlert` modifier reads `kernelModel.storeOpenFailure` directly in its `body` (not only inside a `Binding.get` closure) to ensure correct `@Observable` tracking. When the value is non-nil, it presents a SwiftUI `.alert` with:
- Title: "Storage Unavailable"
- Message: the `storeOpenFailure` reason string
- Dismiss button: "OK" that sets `storeOpenFailure` back to `nil`

The modifier is attached to `RootView`. [^14943-19]

## Delivery Channel Verification

The `store_open_failure` field rides the generic kernel push snapshot frame (the same frame decoded by `nmp_app_podcast_decode_update_frame`). With the FlatBuffers ABI fix applied, the push frame now decodes correctly and carries `store_open_failure` reactively. The field is designed to ride the first post-Start snapshot — the kernel sets `store_open_failure` with `changed_since_emit: true` at construction, so the first running tick after Start flushes that frame. [^14943-20]

## Decode Tests

The `StoreOpenFailureDecodeTests` suite has 4 tests validating the decode path for the `store_open_failure` field in various snapshot envelope shapes. These tests live in the `PodcastrTests` target under `AppTests/Sources/StoreOpenFailureDecodeTests.swift`. [^14943-21]

## See Also
- [[nmp-update-transport|NMP Update Transport (FlatBuffers Push)]] — related guide
- [[nmp-v0-1-0-adoption|NMP v0.1.0 Adoption]] — related guide

