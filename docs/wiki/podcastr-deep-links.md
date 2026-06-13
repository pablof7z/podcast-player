---
title: Podcastr Deep Links
slug: podcastr-deep-links
topic: ui-components
summary: "The `podcastr://e/<guid>` deep-link route is not yet registered"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-14
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:02078283-91db-41b1-80f8-989daef628ac
---

# Podcastr Deep Links

## Deep Links

The `podcastr://` URL scheme is already registered in Info.plist. The `podcastr://e/<guid>` deep-link route remains unregistered, so share and copy actions fall back to the enclosure URL across PlayerShareSheet, PlayerMoreMenu, and EpisodeRowContextMenu. The callback URL `podcastr://nip46` returns to the app without triggering loud logging (DeepLinkHandler.resolve returns nil for the nip46 host).

<!-- citations: [^0f3f2-61] [^02078-6] -->
