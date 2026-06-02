---
title: Android Download Capability
slug: android-download-capability
summary: Android DownloadCapability uses the OkHttp executor with progress and completion reports to the kernel
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

# Android Download Capability

## Android DownloadCapability

Android DownloadCapability uses the OkHttp executor with progress and completion reports to the kernel. Calling detach() must cancel OkHttp calls before joining to avoid a 60-second ANR window. <!-- [^14943-136] -->
