---
title: Auto-Download Settings (NMP v0.1.0)
slug: auto-download-settings
summary: Per-podcast auto-download settings (enabled, wifi_only/cellular_allowed) in Rust PodcastStore with global is_on_wifi and Swift SetAutoDownload host-op integration.
tags:
  - rust
  - swift
  - downloads
  - settings
volatility: cold
confidence: medium
created: 2026-05-30
updated: 2026-06-01
verified: 2026-05-30
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Auto-Download Settings (NMP v0.1.0)

> Per-podcast auto-download settings (enabled, wifi_only/cellular_allowed) in Rust PodcastStore with global is_on_wifi and Swift SetAutoDownload host-op integration.

## Overview

NMP v0.1.0 introduced auto-download settings that were previously managed on the Swift side. The migration moved per-podcast wifi_only and auto_download_enabled flags into Rust's PodcastStore with corresponding FFI host-ops for the Swift UI to dispatch settings changes. <!-- [^14943-65] -->

## Per-Podcast Settings

PodcastStore tracks two per-podcast auto-download settings: auto_download_enabled — a set of podcast IDs with auto-download enabled (present = enabled). auto_download_cellular_allowed — a set of podcast IDs where cellular downloads are explicitly allowed (present = cellular OK). Absent from the cellular set defaults to wifi-only. The wifi_only_for(id) accessor returns !auto_download_cellular_allowed.contains(id) — true (wifi-only) by default unless explicitly opted out. The set_auto_download_cellular_allowed(id, allowed) setter adds/removes from the set. <!-- [^14943-66] -->

## Cleanup on Unsubscribe

When a podcast is unsubscribed, both auto_download_enabled and auto_download_cellular_allowed are cleared for the podcast ID to avoid stale settings accumulating for non-existent podcasts. <!-- [^14943-67] -->

## Global is_on_wifi

PodcastStore maintains a global is_on_wifi: bool flag. The NetworkCapability observer fires ConnectivityChanged reports to the Rust kernel via nmp_app_podcast_network_report to update this flag. is_on_wifi defaults to true (conservative) until the initial report fires. This is distinct from per-podcast wifi settings — it reflects the device's current network state. The episodes_to_auto_download function uses is_on_wifi combined with per-podcast wifi_only_for to determine whether to auto-download new episodes from a feed refresh.

<!-- citations: [^14943-68] [^14943-138] -->
## Swift Settings Dispatch

The Swift UI dispatches auto-download settings changes via the SetAutoDownload action. This host-op carries an enabled boolean and a wifi_only boolean. The handle_set_auto_download handler processes both fields, updating auto_download_enabled and auto_download_cellular_allowed (inverting wifi_only since the set tracks cellular-allowed). The Action struct's wifi_only field defaults to true via #[serde(default = "default_true")]. <!-- [^14943-69] -->
