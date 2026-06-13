---
title: Subscription Download Worker
slug: subscription-download-worker
topic: data-persistence
summary: The worker owns `App/Sources/Services/Subscription*.swift`, `App/Sources/Services/EpisodeDownload*.swift`, `App/Sources/Podcast/RSS*.swift`, `App/Sources/Podcas
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-11
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:rollout-2026-05-11T09-10-30-019e15a8-9588-70a1-99b0-f20d08ac91a4
  - session:rollout-2026-05-11T09-10-31-019e15a8-991d-7890-957e-f45fb0ff5a7c
---

# Subscription Download Worker

## Ownership Scope

The worker owns only .github/workflows/**, ci_scripts/**, Project.swift, App/Resources/Info.plist, App/Widget/Resources/Info.plist, README.md, docs/features.md, docs/spec/PRODUCT_SPEC.md, docs/wiki indexes, and release/config tests/scripts, and must not revert or reformat unrelated files. (Previously: App/Sources/Services/Subscription*.swift, EpisodeDownload*.swift, App/Sources/Podcast/RSS*.swift, FeedClient.swift, DownloadState.swift, AppDelegate.swift, and related tests.)

<!-- citations: [^rollo-114] [^rollo-136] -->
