---
title: Rust Dylib Xcode Integration
slug: rust-dylib-xcode-integration
summary: The Rust dylib for the podcast module is retained (not deleted) with its install name fixed to `@rpath/libnmp_app_podcast.dylib` to avoid duplicate-symbol confl
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-04
updated: 2026-06-04
verified: 2026-06-04
compiled-from: conversation
sources:
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
---

# Rust Dylib Xcode Integration

## Rust Dylib Retention and Rpath

The Rust dylib `libnmp_app_podcast.dylib` is retained (not deleted) with its install name fixed to `@rpath/libnmp_app_podcast.dylib` to avoid duplicate-symbol conflicts with `shake_feedback_core` under LiteRTLM's `-all_load` flag. An Xcode build phase (`Embed Rust Dylib`) copies the dylib into the app bundle and codesigns it with the actual development certificate inside the build phase script—iOS rejects ad-hoc codesigning.

<!-- citations: [^67062-6] [^67062-7] [^67062-11] -->
