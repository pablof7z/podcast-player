---
title: Domain Consistency
slug: domain-consistency
topic: general
summary: The application avoids bidirectional-sync bugs by forbidding Swift-only domain state across projection passes.
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

# Domain Consistency

## Architecture Principles

The application avoids bidirectional-sync bugs by forbidding Swift-only domain state across projection passes. <!-- [^deb49-3] -->
