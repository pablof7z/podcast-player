---
title: Model Download Management
slug: model-download-management
topic: model-download-management
summary: Model downloads are routed through the same background `URLSession` infrastructure as episodes to ensure progress is maintained when the app is suspended or ter
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-05
updated: 2026-06-06
verified: 2026-06-05
compiled-from: conversation
sources:
  - session:e1ab0629-64bc-4383-bd22-c0843ca16a99
  - session:deb49f4f-f275-419a-ab1c-b68c123af73b
---

# Model Download Management

## Model Download Architecture

Model downloads are routed through the same background `URLSession` infrastructure as episodes to ensure progress is maintained when the app is suspended or terminated. Local model downloads implement resume support by capturing and persisting `NSURLSessionDownloadTaskResumeData` to disk. <!-- [^e1ab0-3] -->

## Download Management Logic

The `DownloadCapability` in Swift is kind-aware, using a specific destination path and `taskDescription` prefix (e.g., 'model:<id>') based on whether the item is an episode or a local model. The model download matching logic uses the full download URL for comparison rather than just the filename-basename to ensure successful file moves upon completion. <!-- [^e1ab0-4] -->


The `DownloadCapability` in Swift is kind-aware, using a specific destination path and `taskDescription` prefix (e.g., 'model:<id>') based on whether the item is an episode or a local model. The model download matching logic uses the full download URL for comparison rather than just the filename-basename to ensure successful file moves upon completion.

A separate narrow `downloads_rev` and `downloads_snapshot` are used to ensure the 1 Hz progress stream does not incur full-library costs. <!-- [^deb49-5] -->
## Backend Implementation

The LocalModelDownloadManager is replaced by a shared `DownloadQueue` in Rust that supports multiple download types via a `DownloadKind` discriminant. <!-- [^e1ab0-5] -->
