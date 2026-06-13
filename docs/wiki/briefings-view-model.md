---
title: Briefings View Model
slug: briefings-view-model
topic: agent-system
summary: "BriefingsViewModel uses swiftlint:disable force_try for a try! fallback to the tmp directory."
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-08
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:c33b9adb-9d1a-4717-9314-b45a61e6cbc3
---

# Briefings View Model


## Swift Action Helpers Polling Fix

Issue #321 (Swift action helpers polling) is fixed by replacing Task.sleep(300ms) loops with @Observable reactive awaiters and timeout racers, via PR #348. <!-- [^c33b9-2] -->
