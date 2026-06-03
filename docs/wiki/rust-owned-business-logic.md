---
title: Rust-Owned Business Logic
slug: rust-owned-business-logic
summary: All business logic must be Rust-owned per NMP guidelines — Swift-owned business logic must be migrated to the kernel
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-03
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
---

# Rust-Owned Business Logic

## Rust-Owned Business Logic

All business logic must be Rust-owned per NMP guidelines — Swift-owned business logic must be migrated to the kernel. The preserved-state block in AppStateStore+KernelProjection.swift is fully deleted — all episode state flows through the Rust projection. The UserIdentityStore.shared singleton is deleted — identity is owned by AppStateStore via let identity = UserIdentityStore(). The agent chat feature, including the provider enum, credential resolution, API calls, and tool loop, is fully migrated from Swift into the Rust kernel, leaving Swift only to render streamed tokens.

<!-- citations: [^14943-155] [^4dd36-11] -->
