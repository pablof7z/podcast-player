---
title: Kernel State Mutation Performance
slug: kernel-state-mutation-performance
summary: applyKernelState costs ~29 ms on the main thread per content mutation with 3,615 episodes — a real performance problem causing frame drops.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-02
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
---

# Kernel State Mutation Performance

## Performance Constraint

applyKernelState costs ~29 ms on the main thread per content mutation with 3,615 episodes — a real performance problem causing frame drops. The mutation must not unconditionally rebuild all episode dictionaries; a fast-path guard must skip the O(N) scaffolding when no episodes changed. The `kernelDownload` method must use the canonical `episode(id:)` accessor on `AppStateStore` rather than `state.episodes` to look up episodes, as `state.episodes` is empty after the observation granularity refactor.

<!-- citations: [^14943-145] [^14943-146] [^e1cfd-5] -->
