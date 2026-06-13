---
title: Wiki Triggers
slug: wiki-triggers
topic: wiki-generation
summary: WikiTriggers has zero production callers — `wikiAutoGenerateOnTranscriptIngest` is declared, persisted, and iCloud-synced but has no read site, making the auto-
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-12
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
  - session:rollout-2026-05-11T09-10-31-019e15a8-97f5-7fc2-9daf-4c834d1999b0
---

# Wiki Triggers

## Auto-Generation Pipeline

The auto-refresh pipeline is wired but has three critical bugs: WikiResponseParser defaults page title to slug on audit refresh, WikiStorage.updateInventory lacks a lock allowing concurrent write races, and WikiPrompts.audit omits prior page body causing every refresh to silently downgrade prior claims. (Previously: Wiki settings no longer claim transcript-triggered auto-generation is active; Settings reports Wiki as manual, superseded — see wiki-refresh-executor.) Transcript-triggered auto-refresh is now wired, but the pipeline has three critical bugs: WikiResponseParser defaults page title to slug, WikiStorage.updateInventory has no lock permitting concurrent write races, and WikiPrompts.audit excludes prior page body causing silent downgrades on every refresh. (Previously: Transcript-triggered auto-refresh is not yet wired; the UI says manual instead of overpromising, superseded — see wiki-refresh-executor.)

<!-- citations: [^7f076-22] [^7f076-23] [^rollo-122] -->
