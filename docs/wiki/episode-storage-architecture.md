---
title: Episode Storage Architecture
slug: episode-storage-architecture
topic: data-persistence
summary: Episode mutations must use row-level upsert and delete APIs instead of whole-library SQLite rewrites
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-13
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:rollout-2026-05-11T08-21-01-019e157b-49b7-7663-891c-1c44d125ca44
  - session:rollout-2026-05-11T09-10-29-019e15a8-931d-72c1-93dc-3b602c74874b
  - session:rollout-2026-05-17T17-40-02-019e3661-3d9a-76d3-a4a5-f5779f6a0ee8
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Episode Storage Architecture

## Episode Mutations

EpisodeSQLiteStore exposes transactional row-level upsert, delete, and combined delta APIs. Persistence tracks per-row episode snapshots and uses delta writes for small episode mutations/deletes, with fallback to replaceAll for initial, large, or full rebuild paths. The delta-write path still computes an O(N) episode snapshot/hash to decide the write plan.

SQLite sidecars must use schema versions and migration paths rather than storing model objects as Codable BLOBs, and must columnize any fields the app mutates or queries.

Metadata JSON plus episode SQLite changes are committed atomically together. (Previously: JSON metadata and SQLite are not one atomic transaction across both files; the existing write ordering/fallback behavior is preserved. (Previously: The metadata JSON and the episode SQLite sidecar must be committed atomically together—either by moving metadata into SQLite or by adding a generation manifest and two-phase commit so their versions are validated as a pair on load.), superseded — see episode-audit-events.)

Persistence failures must not silently degrade to empty data. The system must keep last-good backups, quarantine corrupt files, salvage readable rows, and prevent overwriting recovered state until the user acknowledges repair.

Episode lookups must use O(1) projections via an `episodeIndexByID: [UUID: Int]` dictionary instead of O(N) array scans. <!-- [^rollo-158] -->

Feed refresh must batch podcast metadata and episode changes into one mutation batch per refresh sweep, persisting once instead of once per feed or 304 response. <!-- [^rollo-159] -->

The queue-row EpisodeSummary construction uses a shared helper (episode_summary) to guarantee byte-identical output between full-library and slice-local paths. <!-- [^c1691-240] -->

<!-- citations: [^rollo-67] [^rollo-68] [^rollo-69] [^rollo-70] [^rollo-107] -->
## Ownership Scope

Ownership scope is limited to App/Sources/State/Persistence.swift, App/Sources/State/EpisodeSQLiteStore.swift, App/Sources/State/AppStateStore+Episodes.swift, App/Sources/State/AppStateStore+PositionDebounce.swift, and persistence/state tests only. <!-- [^rollo-106] -->

## Durability Tests

Persistence durability tests include delta-write round-trip tests for single-row mutation and delete, and assert that large imports still use full rebuild. <!-- [^rollo-108] -->

## File Size Limits

Persistence.swift and EpisodeSQLiteStore.swift remain above the 300-line soft limit but below the 500-line hard limit. <!-- [^rollo-109] -->
