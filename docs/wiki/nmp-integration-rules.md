---
title: NMP Integration Rules
slug: nmp-integration-rules
summary: "Rules for integrating with NMP: use the canonical snapshot-projection seam, never create bespoke pull symbols, and never use ADR-0037 for basic wiring."
tags:
  - nmp
  - integration
  - projection
  - seam
  - anti-pattern
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-06-01
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# NMP Integration Rules

> Rules for integrating with NMP: use the canonical snapshot-projection seam, never create bespoke pull symbols, and never use ADR-0037 for basic wiring.

## Canonical Seam

NMP provides a single canonical seam for delivering app-level projections: `nmp_app_register_snapshot_projection` (C FFI, `nmp-ffi/src/snapshot.rs:83`) and its Rust counterpart `NmpApp::register_snapshot_projection` (`nmp-ffi/src/lib.rs:1109`, `pub`). Registered projections are appended to `KernelSnapshot::projections` on every tick and ride the reactive push frame. The seam takes a key (e.g., `"podcast.snapshot"`) and a projector function `Fn() -> serde_json::Value + Send + Sync + 'static`. <!-- [^14943-27] -->


The podcast app uses the raw C-ABI path (`nmp_app_new` → `register` → `start`), not `NmpAppBuilder`, so relay seeding uses `set_initial_relays_for_start` instead of `with_relay()`. This call must be made before `start()`. <!-- [^14943-112] -->

## Anti-Pattern: Bespoke Pull Symbols

Creating app-private pull symbols (e.g., `nmp_app_podcast_snapshot`, `_rev`, `_free`) and polling them is the deprecated `nmp_app_chirp_snapshot` anti-pattern. This is forbidden. The podcast player previously had such symbols defined in `apps/nmp-app-podcast/src/ffi/snapshot.rs` — they were the self-inflicted cause of the two-channel split (push for generic kernel updates, poll for podcast data) and the 500ms poll (a D8 violation). The correct pattern is to register the projection through the canonical push seam. <!-- [^14943-28] -->

## ADR-0037 Typed Sidecar

ADR-0037's typed FlatBuffers sidecar is a per-key, hot-path optimization rolled out by coordinated cross-host migration (schema + every host's decoder + CI pins). It is NOT an app-facing choice and NOT a prerequisite for getting onto the push channel. The generic projection emission from the registry is the mandatory primary transport. The typed sidecar should not be used to solve wiring problems. <!-- [^14943-29] -->

## FlatBuffers Decode

The `nmp_core` crate (a dependency of NMP, not the app) exposes `decode_snapshot_payload(&[u8]) -> Value` and `decode_update_frame(&[u8]) -> UpdateEnvelope` for decoding binary FlatBuffers frames. The app's Rust crate calls these through its `nmp_app_podcast_decode_update_frame` FFI helper to convert binary frames into the JSON envelope shape the Swift shell expects. <!-- [^14943-30] -->

## Emit and Rev Model

The kernel emits push frames only on `changed_since_emit`. The podcast `rev` is bumped synchronously inside `DispatchHostOp` handlers (which already call `maybe_emit_after_dispatch`) or shell-initiated FFI report handlers (which do NOT emit — they were designed for a follow-up pull). The host seam `ActorCommand::MarkChangedSinceEmit` (via `NmpApp::send_cmd`/`actor_sender()`) can force an emit if needed. No background task bumps `rev` autonomously. <!-- [^14943-31] -->


The `discover_nostr` action registers an `ActorCommand::EnsureInterest` for kind:10154 with `InterestLifecycle::OneShot` and `is_indexer_discovery: true`, without specifying a relay URL — NMP routes through the user's configured app relays and NIP-65 outbox read relays automatically. The user's app relays should not need to be specified per-request; they are configured once as app relays and NMP uses them automatically for all subscriptions. <!-- [^14943-113] -->

## Business Logic Ownership

All business logic must be Rust-owned per NMP guidelines — Swift is a rendering shell only. <!-- [^14943-114] -->

## Synthetic Episodes

Synthetic episodes (agent TTS) must be registered in the Rust kernel via a `RegisterSyntheticEpisode` action so they survive kernel projection and NIP-F4 publish can find them. <!-- [^14943-115] -->

## UI Component Selection

NMP UI components (Nostr identity surfaces) should not be adopted for the podcast iOS app — the custom views are tighter and design-aligned. A backlog note exists to render NIP-05 badges (the field is parsed but never shown). <!-- [^14943-116] -->

## See Also
- [[podcast-projection-registration|Podcast Projection Registration]] — related guide
- [[reactive-update-model|Reactive Update Model (No Polling)]] — related guide
- [[nmp-version-upgrades|NMP Version Upgrades]] — related guide
- [[security-and-constraints|Security and Constraints]] — related guide

