---
title: Podcast Title Placeholder
slug: podcast-title-placeholder
topic: data-persistence
summary: The Podcast model has a titleIsPlaceholder flag that is set true at all four placeholder-construction sites and cleared only after a successful feed fetch
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-08
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
  - session:8eb3f00f-b245-4f03-80f0-15151d9aba28
---

# Podcast Title Placeholder

## Title Placeholder Flag

The Podcast model has a titleIsPlaceholder flag that is set true at all four placeholder-construction sites and cleared only after a successful feed fetch. Codable migration uses `decodeIfPresent ?? false`. feed_url is an Option<Url> — absent for feed-less podcasts, not a defining property. The kernel stores all podcasts uniformly and the library projection emits all of them. New feeds get a host-placeholder title on optimistic insert; known feeds keep their cached episodes.

<!-- citations: [^0f3f2-60] [^55bed-15] [^8eb3f-10] -->
