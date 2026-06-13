---
title: Diagnostic Log
slug: diagnostic-log
topic: project-setup
summary: The Settings > Debug > Logs feature uses an in-memory ring buffer (500 entries, DiagnosticLog singleton) with a toggle defaulting to off, ensuring zero overhead
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-02
updated: 2026-06-12
verified: 2026-06-02
compiled-from: conversation
sources:
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
---

# Diagnostic Log

## Diagnostic Log

The Diagnostics view is rewired to read events directly from the kernel via a lazy FFI getter, and the redundant Swift EpisodeAuditLogStore is deleted, replacing the in-memory DiagnosticLog ring-buffer approach. (Previously: The Settings > Debug > Logs feature uses an in-memory ring buffer (500 entries, DiagnosticLog singleton) with a toggle defaulting to off, ensuring zero overhead when disabled via @autoclosure on append(message:), superseded — see episode-audit-events.) The toggle is stored in UserDefaults and the UI provides a Settings > Debug section with the toggle, a link to the log viewer, and color-coded entries with copy-all and clear actions. <!-- [^e1cfd-2] -->

## Diagnostic Tap Points

Diagnostic tap points are: kernel snapshot ticks (rev + episode count), download events, audio commands, every kernel.dispatch call, store open failure, and app foreground/background via scenePhase. <!-- [^e1cfd-3] -->

## Lifecycle Logging

Lifecycle logging uses SwiftUI's scenePhase switch in AppMain.swift rather than AppDelegate lifecycle methods, because the app is scene-based and AppDelegate methods like applicationDidBecomeActive never fire when scenes are active. <!-- [^e1cfd-4] -->
