---
title: Episode Chapters
slug: episode-chapters
topic: chapter-compilation
summary: "Episode.Chapter includes an optional `summary: String?` field (Codable-backward-compatible)"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-08
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
  - session:513924f8-3b98-47b0-a84a-38086416581a
  - session:84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
  - session:ede5e5c5-01cb-4985-aae5-6a4e1b09fc08
---

# Episode Chapters

## Episode Chapter Model & Display

Episode.Chapter uses linkURL (not url) and title is non-optional (not Optional<String>). Chapters display only titles, not descriptions or summaries. Chapter timestamps are positioned on the right column. The active chapter has no background and no playing icon; its title is displayed in bold and black, while inactive chapter titles are displayed in regular weight and a slightly muted color. Chapters do not display an AI label. Chapters are generated as a side-effect of an episode having been downloaded.

<!-- citations: [^7f076-7] [^51392-1] [^84c4d-10] [^ede5e-2] -->
