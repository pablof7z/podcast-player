---
title: Performance Profiling
slug: performance-profiling
topic: general
summary: To identify which layer dominates performance, reconcile, build, and profile the current hot path on an iOS simulator
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-06
updated: 2026-06-06
verified: 2026-06-06
compiled-from: conversation
sources:
  - session:deb49f4f-f275-419a-ab1c-b68c123af73b
---

# Performance Profiling

## Performance Profiling

To identify which layer dominates performance, reconcile, build, and profile the current hot path on an iOS simulator. This process identifies whether the bottleneck lies within Swift JSON decoding, the Rust rebuild/serialization logic, or the final projection layer. <!-- [^deb49-6] -->
