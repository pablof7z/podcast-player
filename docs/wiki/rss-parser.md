---
title: RSS Parser
slug: rss-parser
topic: data-persistence
summary: "RSSParser tolerates `<podcast:value>` and `<podcast:location>` tags but does not explode them."
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:rollout-2026-05-11T08-21-02-019e157b-4b15-77a0-8003-a3ae75cf8c26
  - session:rollout-2026-05-11T09-10-30-019e15a8-9588-70a1-99b0-f20d08ac91a4
---

# RSS Parser

## Vendor Extension Handling

RSSParser tolerates `<podcast:value>` and `<podcast:location>` tags but does not explode them.

NaN/infinity float values from RSS parse_duration propagate through ChapterSummary.start_secs, serialize as JSON null, and cause the entire PodcastUpdate frame to be dropped on the Swift side — this is remotely triggerable from any RSS feed via `<itunes:duration>NaN</itunes:duration>`.

parse_duration rejects NaN, Inf, and negative values at the inlet, and projection-side finite guards clamp any remaining NaN/Inf to 0.0 for required float fields, preventing a remotely-triggerable UI freeze from malformed RSS duration values.

AppStateStore RSS merge policy was dead code (all production callers guard-then-insert or pass all-new episodes); the kernel projection full-replaces .rss rows every tick.

Feed parsing ignores feed-relative URLs, causing feeds with relative or protocol-relative media URLs to import successfully but fail later in playback, download, artwork, or transcript flows. Relative and protocol-relative URLs must be resolved against `feedURL`.

Bad or missing `pubDate` must fall back to epoch (a stable old timestamp) rather than `Date()` (now), so broken feeds do not appear newly published. (Previously: Bad or missing `pubDate` falls back to `Date()`, causing malformed old episodes to jump to the top and skew sorting, auto-download latest-N choices, and notifications.)

<!-- citations: [^0f3f2-63] [^c1691-14] [^14943-23] [^c1691-49] [^rollo-92] [^rollo-113] [^c1691-84] [^c1691-146] -->
