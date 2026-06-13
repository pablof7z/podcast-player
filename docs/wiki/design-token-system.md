---
title: Design Token System
slug: design-token-system
topic: ui-components
summary: Episode detail section dividers use `AppTheme.Tint.hairline` and `AppTheme.Tint.dimmed` design tokens rather than hardcoded `Color.secondary.opacity` values
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-15
updated: 2026-05-15
verified: 2026-05-15
compiled-from: conversation
sources:
  - session:a42285c2-863e-42d1-a433-e7bf25bcfc21
---

# Design Token System

## Design Tokens

Episode detail section dividers use `AppTheme.Tint.hairline` and `AppTheme.Tint.dimmed` design tokens rather than hardcoded `Color.secondary.opacity` values. Wiki confidence colors use `AppTheme.Tint.evidenceHigh/Medium/Low` tokens instead of hardcoded RGB triples. Threading contradiction colors use `AppTheme.Tint.threadingContradiction` and `evidenceMedium/Low` tokens instead of hardcoded colors. Voice state colors use `AppTheme.Tint.voiceListening/Thinking/Speaking` tokens instead of hardcoded values. `WikiPageView` error color uses `AppTheme.Tint.error` instead of a hardcoded RGB value. <!-- [^a4228-1] -->

## Typography

No serif fonts are used; all text uses the SF system font. Episode titles render in normal case across all surfaces, not uppercased. Podcast names render in their natural casing on home cards and player, without `.textCase(.uppercase)` or letter-tracking overrides. <!-- [^a4228-2] -->

## Artwork

All artwork placeholders across the app are unified to `Color.secondary.opacity(0.18)` + waveform icon. `CachedAsyncImage` calls include `targetSize` parameters where artwork is rendered at known dimensions (episode detail hero, home resume card, home agent pick card, player compact artwork) to avoid decoding full-resolution images. <!-- [^a4228-3] -->

## Consistency Fixes

Obvious UI consistency issues are fixed immediately without asking; non-obvious issues are presented as a list for the user to decide on. <!-- [^a4228-4] -->
