---
title: M3 Settings and Credentials Migration
slug: m3-settings-credentials
summary: "M3 migrates all settings and credentials into the Rust kernel: SettingsSnapshot expansion, iCloudSettingsSync deletion, and OpenRouter/Ollama to PcstIdentityCapability Keychain slots."
tags:
  - m3
  - settings
  - credentials
  - rust
  - migration
volatility: warm
confidence: medium
created: 2026-05-30
updated: 2026-05-30
verified: 2026-05-30
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# M3 Settings and Credentials Migration

> M3 migrates all settings and credentials into the Rust kernel: SettingsSnapshot expansion, iCloudSettingsSync deletion, and OpenRouter/Ollama to PcstIdentityCapability Keychain slots.

## Overview

M3 moves all settings and credentials into the Rust kernel. The goal is to delete iCloudSettingsSync and migrate OpenRouter/Ollama credentials to the PcstIdentityCapability Keychain slots. The migration-v2.md done-when criteria: no @AppStorage domain settings, all settings projected with ops, iCloudSettingsSync deleted, OpenRouter/Ollama to Keychain. [^14943-88]

## Current State (~40% done)

Prior to M3, settings are split across two systems. The old iCloudSettingsSync is still live at AppStateStore.swift:234,261,282,288 and AppStateStore+MutationBatch.swift:61, syncing settings via iCloud. The new iCloudSyncCapability only syncs 5 of ~55 settings fields. Settings.swift has ~55 fields; SettingsSnapshot (the Rust projection) has only 8. The updateSettings host-op dispatches only a few settings; most are Swift-only. Credentials: OpenRouterCredentialStore and OllamaCredentialStore still use Swift keychain wrappers rather than the PcstIdentityCapability Keychain slots. [^14943-89]

## Workstreams

M3 has two distinct but parallelizable workstreams: (1) SettingsSnapshot expansion — add defaultPlaybackRate, autoDeleteDownloadsAfterPlayed, notifyOnNewEpisodes, notifyOnBriefingReady, STT/TTS/AI model IDs, and all remaining settings fields to the Rust projection, with corresponding host-ops for the Swift UI to dispatch. iCloud sync must cover all projected fields. (2) Credential migration — OpenRouterCredentialStore and OllamaCredentialStore migrated to PcstIdentityCapability Keychain slots, with legacyOpenRouterAPIKey removed from the Swift compat layer. [^14943-90]

## See Also

