---
title: Wiki Refresh Executor
slug: wiki-refresh-executor
topic: wiki-generation
summary: WikiRefreshExecutor (~175 lines) provides in-flight dedup by (slug, scope), â¤3 concurrent jobs, FIFO drain, and silent skip on missing API key
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
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Wiki Refresh Executor

## Core Behavior

WikiRefreshExecutor (~175 lines) provides in-flight dedup by (slug, scope), ≤3 concurrent jobs, FIFO drain, and silent skip on missing API key. <!-- [^7f076-20] -->

## Known Bugs

Three critical bugs exist in the auto-refresh pipeline:

1. **WikiResponseParser** defaults page title to slug on audit refresh, corrupting titles.
2. **WikiStorage.updateInventory** has no lock, allowing concurrent writes to race.
3. **WikiPrompts.audit** doesn't include prior page body, causing every refresh to silently downgrade prior claims.
4. Naively sharing `Arc<AtomicBool>` for re-entrancy guards can drop a subscribe-completion trigger while a refresh pass is mid-flight; the fix requires a run-again/dirty flag, making it M not S scope.

<!-- citations: [^7f076-21] [^c1691-127] -->
