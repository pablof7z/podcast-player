---
title: Performance Metrics
slug: performance-metrics
topic: diagnostics
summary: The Performance metrics feature is off by default
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-06
updated: 2026-06-06
verified: 2026-06-06
compiled-from: conversation
sources:
  - session:57b63f46-0a23-4efc-b087-0a521300d906
---

# Performance Metrics

## Performance Metrics

The Performance metrics feature is off by default. When disabled, the instrumentation is a no-op (one clock read + a `defer` record per site). The feature makes no behavioral change to the FFI bridge. <!-- [^57b63-1] -->

The iOS app provides a Debug → Performance view containing a live HUD of FFI bridge traffic and main-thread stall metrics. <!-- [^57b63-2] -->

The main-thread stall watchdog probes the main queue ~20×/s, measuring wait latency to catch any UI block, and buckets stalls into jank (≥80ms), hang (≥250ms), and worst-stall. <!-- [^57b63-3] -->

Per-operation stats track count, avg, max, and payload bytes for push-frame decode, main·apply, main·projection, FFI dispatch, and snapshot pull. <!-- [^57b63-4] -->

The dead `time<T>` method on the collector is removed from the public API (all sites use manual `defer` timing). <!-- [^57b63-5] -->

The in-app toggle's visual flip under UI automation is unconfirmed due to the 1Hz live-refresh Timer dropping simulated taps mid-rebuild, though the enable-via-defaults path accumulated over 5,500 samples live. <!-- [^57b63-6] -->
