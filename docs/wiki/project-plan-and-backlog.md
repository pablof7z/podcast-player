---
title: Project Plan and Backlog
slug: project-plan-and-backlog
summary: The project's ordered M0-M8 migration sequence, current state after NMP v0.1.0 adoption, and items explicitly deleted from the backlog.
tags:
  - planning
  - migration
  - backlog
volatility: warm
confidence: medium
created: 2026-05-30
updated: 2026-05-30
verified: 2026-05-30
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Project Plan and Backlog

> The project's ordered M0-M8 migration sequence, current state after NMP v0.1.0 adoption, and items explicitly deleted from the backlog.

## Overview

migration-v2.md defines the ordered M0-M8 execution sequence for migrating all features from the legacy App/Sources/ to the NMP kernel. The plan superseded the feature-parity matrix as the operative roadmap. The sequence is: M1 PlaybackState → M2 Downloads → M3 Settings/Credentials → M4 Preserved State → M5 AI Scaffolds Become Real → M6 Keys to Keychain → M7 Compat Burn-Down → M8 Delete App/Sources/. [^14943-70]

## Current State (Post NMP v0.1.0)

After the NMP v0.1.0 adoption, M1 (playback engine swap), and M2 (download path unification), the project's status is: the wiring and data flow are done and working, and M1+M2 are merged to main. M1 (PR #138) delivered: AudioEngine→AudioCapability kernel bridge, PlaybackState as a ~205-line pure renderer, reactive playback with position persistence, segment-end advancement, auto-advance on the canonical PlaybackQueue, and 4 codex-found playback regressions fixed. M2 (PR #139) delivered: wifi_only auto-download gating in Rust, total_bytes in DownloadItemSnapshot, NetworkCapability reactive connectivity monitoring, and a deferred-download system for cellular-blocked episodes with persisted pending_wifi_downloads and full revalidation before dispatch. The product — especially the entire AI layer — is mostly scaffold. The next milestone is M3 (settings/credentials in Rust, ~40% done). The backlog's remaining buckets include P0 correctness (Keychain, relay publish/discovery, validation gate), P1 ownership, P1 social/Nostr, P1 AI, and platform items.

<!-- citations: [^14943-71] [^14943-86] -->
## Deleted Items

Three items were explicitly deleted from the backlog during the NMP v0.1.0 framing revision: (1) p0-nipf4-legacy-data — no legacy data migration needed since NMP is the only implementation. (2) NIP-74 migration — NIP-F4 is canonical; NIP-74 survives only as code-symbol names and anti-re-entry test guards. (3) NIP-17 work — agent-to-agent uses kind:1/NIP-10; NIP-17 is an explicit non-goal everywhere. [^14943-72]

## See Also

