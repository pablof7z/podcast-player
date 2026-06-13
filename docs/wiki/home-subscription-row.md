---
title: Home Subscription Row
slug: home-subscription-row
topic: ui-components
summary: HomeSubscriptionRow shows 'No episodes yet' and '—' as fallbacks.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-15
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:a42285c2-863e-42d1-a433-e7bf25bcfc21
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
---

# Home Subscription Row

## HomeSubscriptionRow

HomeSubscriptionRow shows 'No episodes yet' and '—' as fallbacks. It does not display an unplayed count badge; the unplayedCount parameter was removed from the view and its call site.

Episode row primary actions must use an extracted `EpisodeRowContainer` component with explicit policies (`.openDetails`, `.play`, `.playAtTimeAndOpen`) instead of varying per-surface behavior. <!-- [^rollo-100] -->

<!-- citations: [^0f3f2-40] [^a4228-5] -->
