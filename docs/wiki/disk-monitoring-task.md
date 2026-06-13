---
title: Disk Monitoring Task
slug: disk-monitoring-task
topic: data-persistence
summary: The disk monitoring task triggers cleanup when free space drops below 5 GB
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-13
updated: 2026-06-13
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:16ac1219-405e-4d37-bcba-f2ad417a7e1e
---

# Disk Monitoring Task

## Disk Monitoring Task

The disk monitoring task triggers cleanup when free space drops below 5 GB. The task targets at least 80 GB of free space after cleanup. The task must not lose anything important during cleanup. Build artifacts are located in Library, ~/src, and ~/Work. <!-- [^16ac1-2] -->
