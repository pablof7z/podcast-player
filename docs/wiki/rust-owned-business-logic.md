---
title: Rust-Owned Business Logic
slug: rust-owned-business-logic
summary: All business logic must be Rust-owned per NMP guidelines — Swift-owned business logic must be migrated to the kernel
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

# Rust-Owned Business Logic

## Rust-Owned Business Logic

All business logic must be Rust-owned per NMP guidelines — Swift-owned business logic must be migrated to the kernel. The preserved-state block in AppStateStore+KernelProjection.swift is fully deleted — all episode state flows through the Rust projection. The UserIdentityStore.shared singleton is deleted — identity is owned by AppStateStore via let identity = UserIdentityStore(). <!-- [^14943-155] -->
