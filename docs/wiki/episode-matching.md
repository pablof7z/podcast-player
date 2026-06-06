---
title: Episode Matching
slug: episode-matching
topic: episode-matching
summary: The Rust kernel's `episode_enclosure_url` function performs a case-insensitive UUID comparison to correctly match iOS uppercase UUID strings with stored lowerca
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-04
updated: 2026-06-04
verified: 2026-06-04
compiled-from: conversation
sources:
  - session:56e47844-b4ff-4402-9528-c704eade1d7b
---

# Episode Matching

## Episode Matching Logic

The Rust kernel's `episode_enclosure_url` function performs a case-insensitive UUID comparison to correctly match iOS uppercase UUID strings with stored lowercase identifiers. <!-- [^56e47-1] -->
