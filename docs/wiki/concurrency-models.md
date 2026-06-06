---
title: Concurrency Models
slug: concurrency-models
topic: general
summary: O(N×M) hashing is performed off the MainActor via `Task.detached` on the push path.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-06
updated: 2026-06-06
verified: 2026-06-06
compiled-from: conversation
sources:
  - session:deb49f4f-f275-419a-ab1c-b68c123af73b
---

# Concurrency Models

## Hash Computation

O(N×M) hashing is performed off the MainActor via `Task.detached` on the push path. <!-- [^deb49-1] -->
