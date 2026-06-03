---
title: App Lifecycle and Scene Phase
slug: app-lifecycle-scene-phase
summary: App lifecycle events (foreground/background) must be observed via `@Environment(\.scenePhase)` in `AppMain.swift` rather than `AppDelegate` methods, because the
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-02
updated: 2026-06-02
verified: 2026-06-02
compiled-from: conversation
sources:
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
---

# App Lifecycle and Scene Phase

## Scene-Based Lifecycle

App lifecycle events (foreground/background) must be observed via `@Environment(\.scenePhase)` in `AppMain.swift` rather than `AppDelegate` methods, because the app is scene-based and `AppDelegate` lifecycle methods never fire when scenes are active. The `AppDelegate` is retained only for background URL session reconnection and Siri shortcuts, not for lifecycle management. <!-- [^e1cfd-2] -->
