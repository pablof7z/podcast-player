---
title: Vectors Database
slug: vectors-database
topic: data-persistence
summary: The vectors.sqlite database is stored at a path under the app's Application Support/podcastr/ directory on iOS.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
---

# Vectors Database

## Storage Location

The vectors.sqlite database is stored at a path under the app's Application Support/podcastr/ directory on iOS. SQLite-vec is used for RAG storage; JSON is used for settings and similar lightweight data.

<!-- citations: [^67062-9] [^55bed-17] -->
