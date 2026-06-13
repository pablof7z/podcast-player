---
title: Auto Snip Banner
slug: auto-snip-banner
topic: playback
summary: "The banner's tap area is intentionally disabled: `onTap` is an empty callback and the view is installed with `.allowsHitTesting(false)`, making taps fully dead"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-03
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
---

# Auto Snip Banner

## AutoSnipBanner

The banner's tap area is intentionally disabled: `onTap` is an empty callback and the view is installed with `.allowsHitTesting(false)`, making taps fully dead UI. Enabling taps would require a no-transcript composer mode for `ClipComposerSheet`, which currently depends on a full `Transcript+Segment` that `AutoSnipController` cannot provide in the no-transcript case. <!-- [^0f3f2-17] -->

## AutoSnipController

`formatSummary` computes the clipped duration from the real `endSeconds - startSeconds` instead of returning a hardcoded value. (Previously: it discarded both arguments and returned the hardcoded string 'Snipped · 30s clipped' regardless of actual duration.) <!-- [^0f3f2-18] -->

Wires the bookmarkCommand on app startup. <!-- [^67062-3] -->
