---
title: Storage Coordinator
slug: storage-coordinator
topic: data-persistence
summary: A `StorageCoordinator` must be introduced to handle full erasure and per-subscription cleanup
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-11
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:rollout-2026-05-11T08-21-01-019e157b-49b7-7663-891c-1c44d125ca44
  - session:rollout-2026-05-11T08-21-02-019e157b-4b15-77a0-8003-a3ae75cf8c26
---

# Storage Coordinator

## Storage Coordinator

A `StorageCoordinator` must be introduced to handle full erasure and per-subscription cleanup. "Clear All Data" must clear all ancillary stores—transcripts, downloads, vectors, wiki pages, briefings, chat history, agent run logs, and the usage ledger—and not just `AppState` plus Spotlight. Currently, subscription removal and "Clear All Data" leave download files behind, with only Storage Settings later surfacing them as orphan files.

<!-- citations: [^rollo-73] [^rollo-93] -->
## Data Export

Full data export must either be renamed as export-only or implement a restore/migration path. For large libraries, generation must occur off the main actor, potentially as a zipped bundle with sidecars. <!-- [^rollo-74] -->
