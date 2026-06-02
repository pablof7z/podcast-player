---
title: NIP-F4 Key Persistence
slug: nip-f4-key-persistence
summary: NIP-F4 key persistence uses a write-through save() strategy with atomic tmp+rename
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

# NIP-F4 Key Persistence

## Write-Through Persistence

NIP-F4 key persistence uses a write-through save() strategy with atomic tmp+rename. Before writing, create_dir_all is called to ensure the target directory exists. The persisted file uses a JSON envelope with schema_version:1. <!-- [^14943-149] -->
