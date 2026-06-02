---
title: Event-Driven Update Protocol
slug: event-driven-update-protocol
summary: The 500ms snapshot poll is eliminated; updates are fully event-driven via push frames for dispatched changes and one-shot rev-gated pulls for shell-initiated re
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-30
updated: 2026-06-01
verified: 2026-05-30
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Event-Driven Update Protocol

## Update Protocol

The 500ms snapshot poll is eliminated; updates are fully event-driven via push frames for dispatched changes and one-shot rev-gated pulls for shell-initiated reports (audio, download, voice). Nostr code must be reactive with no polling — the 500ms poll was removed entirely in PR #136 and replaced with reactive hooks (onSnapshotMaybeChanged).

<!-- citations: [^14943-97] [^14943-142] -->
