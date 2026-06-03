---
title: M2 Download Path Unification
slug: m2-download-path-unification
summary: "M2 unified the download path: wifi_only gating moved to Rust, total_bytes exposed in the snapshot, and NetworkCapability provides reactive connectivity monitoring."
tags:
  - migration
  - downloads
  - rust
  - swift
volatility: cold
confidence: medium
created: 2026-05-30
updated: 2026-06-03
verified: 2026-05-30
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
---

# M2 Download Path Unification

> M2 unified the download path: wifi_only gating moved to Rust, total_bytes exposed in the snapshot, and NetworkCapability provides reactive connectivity monitoring.

## Overview

Milestone M2 from migration-v2.md is the download path unification. Prior to M2, download orchestration was split: the Rust kernel handled download lifecycle but wifi_only gating was Swift-only, and total_bytes (expected byte count) was absent from the projected snapshot. Audit revealed M2 was ~60% done already: EpisodeDownloadService*.swift were already deleted, URLSession handoff to Rust was done, and the rename from EpisodeDownloadStore to DownloadCapability+Storage.swift had been completed in M1. <!-- [^14943-43] -->

Manual download requests—triggered by swiping or tapping a download button on an episode—are wired end-to-end: the UI dispatches a `kernelDownload` action to the kernel (looking up episodes via the canonical `episode(id:)` accessor on `AppStateStore`), which routes it through the Rust `DownloadQueue` as a `DownloadCommand::StartDownload` to `DownloadCapability` for actual byte transfer via a `URLSession` `downloadTask`. Swift passes the `enclosureURL` directly in the dispatch body so that `handle_download` uses it if present and falls back to its own store lookup otherwise. <!-- [^e1cfd-6] -->

EpisodeSummary.toEpisode() must map download states of `.queued` and `.downloading` from the DownloadQueueSnapshot (PodcastUpdate.downloads.active), not just `.downloaded` and `.notDownloaded`. [^e1cfd-12]

<!-- citations: [^14943-43] [^e1cfd-6] [^e1cfd-11] -->

<!-- citations: [^14943-43] [^e1cfd-6] [^e1cfd-12] [^e1cfd-11] [^e1cfd-15] -->
## total_bytes in DownloadItemSnapshot

Rust's DownloadItem already included a total_bytes: Option<u64> field, but it was not exposed in the DownloadItemSnapshot that rides the podcast projection. The fix added total_bytes to the Rust DownloadItemSnapshot struct, which populates the Swift mirror. This enables the UI to display expected download sizes for in-progress downloads. <!-- [^14943-44] -->

## wifi_only Auto-Download Gate

The wifi_only auto-download setting was managed by Swift's AutoDownloadPolicy.wifiOnly per podcast but Rust completely ignored it. The fix moved wifi_only gating into Rust with a three-part implementation: (1) a per-podcast wifi_only flag stored in PodcastStore settings, (2) a global is_on_wifi state reported from iOS to Rust via the nmp.network.is_on_wifi report capability, and (3) the episodes_to_auto_download function parameterized with wifi_only_on to skip eligible episodes when on cellular and the per-podcast wifi_only flag is set. <!-- [^14943-45] -->

## Per-Podcast Cellular-Allowed Set

The per-podcast wifi_only toggle is stored as a cellular_allowed set in PodcastStore. When a podcast ID is present in the set, cellular downloads are explicitly allowed (user opted out of wifi-only for that show). Absent = wifi-only (the default). The accessors are auto_download_cellular_allowed_for(id) and set_auto_download_cellular_allowed(id, allowed). This set is cleared alongside auto_download_enabled when unsubscribing. <!-- [^14943-46] -->

## NetworkCapability

NetworkCapability.swift wraps Apple's NWPathMonitor to provide reactive connectivity monitoring. It fires an nmp.network.capability report via nmp_app_podcast_network_report(ptr, is_on_wifi) when connectivity changes. This is wired through KernelBridge+Callbacks.swift's attachNetworkReportChannel and initialized from KernelModel.init(). The NWPathMonitor callback captures the kernel handle via a raw pointer; it must null-guard (return early if nil) since the handle may not be set yet at init time. <!-- [^14943-47] -->

## SetAutoDownload Extended for wifi_only

The SetAutoDownload action was extended to carry wifi_only alongside the existing bool toggle. This allows the Swift UI to dispatch a single host-op that sets both auto_download_enabled and auto_download_cellular_allowed in one call. The handle_set_auto_download handler processes both fields. A default_true serde helper was added for the Action struct's new wifi_only field (which defaults to true). <!-- [^14943-48] -->

## Codex Review Findings

Codex found two P1 issues: (1) set_wifi_only was never called from Swift — the existing iOS path only dispatched set_auto_download with a bool, ignoring wifiOnly, rendering the feature inoperative. (2) Episodes seen during a cellular refresh were discarded permanently — their guids ended up in existing_guids, blocking them from ever being auto-downloaded on subsequent Wi-Fi refreshes. These were fixed by extending SetAutoDownload to carry wifi_only and deferring the cellular-discard issue to a tracked backlog item. <!-- [^14943-49] -->

## M2 Scope Boundaries

M2 correctly deferred several items that were already completed or out of scope: the EpisodeDownloadStore → DownloadCapability+Storage rename was already done in M1, and Compat/ServiceStubs.swift download shims were never present (blocked on M3 OpenRouter/BYOK and M6 Nostr keys). <!-- [^14943-50] -->


Codex Review Findings

Codex round 2 found two P1 issues: (1) set_wifi_only was never called from Swift — the existing iOS path dispatched only set_auto_download with a bool, ignoring wifiOnly, rendering the feature inoperative. Fixed by extending SetAutoDownload to carry wifi_only alongside the enabled flag. (2) Episodes seen during a cellular refresh were discarded permanently — their guids ended up in existing_guids, blocking them from ever being auto-downloaded on subsequent Wi-Fi refreshes. Fixed by implementing a deferred-download system: when wifi_only gating blocks downloads, new episodes are stored in pending_wifi_downloads (persisted to disk) and a DispatchDeferredWifiDownloads action is triggered when Wi-Fi is restored. <!-- [^14943-79] -->

Codex round 3 found three P2 issues: (1) wifi_only not round-tripped in PodcastSummary projection — the UI overwrote it to true on every snapshot tick because the field was absent. Fixed by adding cellular_allowed to the PodcastSummary projection and Swift mirror, and updating AppStateStore+KernelProjection.swift to read summary.cellularAllowed when rebuilding the auto-download policy. (2) auto_download_cellular_allowed not persisted to podcasts.json. Fixed by adding the field to PersistedPodcast and the load/save paths. (3) Deferred downloads not revalidated before dispatch — could download episodes from unsubscribed shows. Fixed by adding a revalidation guard in handle_dispatch_deferred_wifi_downloads that checks subscription status, auto-download policy, local file existence, and current network state. <!-- [^14943-80] -->

Codex round 4 found one P2: pending_wifi_downloads not persisted to disk — deferred downloads were lost on app kill. Fixed by adding the list to PersistedSettings and PersistedStore with #[serde(default)], and loading it in set_data_dir. Codex round 5 found one P2: deferred downloads never dispatched on cold launch because isOnWifi started as true, so the first NWPathMonitor update (also Wi-Fi) saw wasOnWifi == true → !wasOnWifi == false and never called onWifiRestored. Fixed by initializing isOnWifi = false so the first Wi-Fi update always triggers onWifiRestored. The Rust handler already handles the empty list cleanly (returns {"dispatched":0}), so this is safe on fresh installs. <!-- [^14943-81] -->

wifi_only Auto-Download Gate

When wifi_only gating blocks downloads during a cellular feed refresh, new episodes are NOT discarded. Instead, they are stored in a pending_wifi_downloads list on PodcastStore, persisted to podcasts.json. When Wi-Fi is restored, a DispatchDeferredWifiDownloads action is dispatched from NetworkCapability.onWifiRestored. The Rust handler drains the pending list and dispatches downloads after full revalidation: subscription still active, auto-download still enabled for the show, wifi_only policy still allows it, and no local file already exists for the episode. Entries that fail revalidation are dropped from the pending list to prevent accumulation. The list survives app restarts via persistence to PersistedSettings.pending_wifi_downloads with #[serde(default)]. For the cold-launch edge case, isOnWifi starts as false in Swift so the first NWPathMonitor update always triggers onWifiRestored, even if the device is already on Wi-Fi. <!-- [^14943-82] -->
