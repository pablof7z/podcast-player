---
title: Kernel State Mutation Performance
slug: kernel-state-mutation-performance
summary: applyKernelState costs ~29 ms on the main thread per content mutation with 3,615 episodes — a real performance problem causing frame drops.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-01
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Kernel State Mutation Performance

## Performance Constraint

applyKernelState costs ~29 ms on the main thread per content mutation with 3,615 episodes — a real performance problem causing frame drops. <!-- [^14943-145] -->

The mutation must not unconditionally rebuild all episode dictionaries; a fast-path guard must skip the O(N) scaffolding when no episodes changed. <!-- [^14943-146] -->
