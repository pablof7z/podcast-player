---
title: Wiki Data Model
slug: wiki-data-model
topic: wiki-generation
summary: No `decodeIfPresent` is used in any Wiki Codable type (`WikiPage`, `WikiSection`, `WikiClaim`, `WikiCitation`, `WikiInventory.Entry`); adding any field is a bre
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-11
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
---

# Wiki Data Model

## Data Model Constraints

No `decodeIfPresent` is used in any Wiki Codable type (`WikiPage`, `WikiSection`, `WikiClaim`, `WikiCitation`, `WikiInventory.Entry`); adding any field is a breaking decode change that causes pages to silently disappear from home. <!-- [^7f076-12] -->

WikiPage schema is missing `volatility`, `verified`, and `compiled-from` fields, which are required for the freshness model (decay half-lives, human verification timestamps, source-vs-conversation provenance). <!-- [^7f076-13] -->

WikiPage now carries a `schemaVersion` field (default 1); `WikiStorage.read`/`allPages` skip pages written under a newer version. <!-- [^7f076-14] -->

Custom `decodeIfPresent`-based inits were added to `WikiPage`, `WikiSection`, `WikiClaim`, `WikiCitation`, and `WikiInventory.Entry` so older on-disk JSON keeps round-tripping. <!-- [^7f076-15] -->
