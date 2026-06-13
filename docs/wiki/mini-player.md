---
title: Mini Player
slug: mini-player
topic: ui-components
summary: The expanded MiniPlayer artwork size is 42pt (reduced 25% from 56pt) and the inline artwork is 26pt (reduced 25% from 34pt).
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-15
updated: 2026-05-15
verified: 2026-05-15
compiled-from: conversation
sources:
  - session:a6b98d9b-32b6-49e0-9bda-3204ca8808bb
  - session:rollout-2026-05-10T20-46-07-019e12ff-1573-7b82-ba04-59c91f91ebce
---

# Mini Player

## Artwork Sizing

The expanded MiniPlayer artwork size is 42pt (reduced 25% from 56pt) and the inline artwork is 26pt (reduced 25% from 34pt). <!-- [^a6b98-3] -->

The expanded MiniPlayer padding is 14pt (horizontal and vertical, hardcoded, not a design token). <!-- [^a6b98-4] -->

## Typography

The expanded MiniPlayer title font is .subheadline.weight(.semibold). The expanded MiniPlayer metadata line font is AppTheme.Typography.caption and the clock font is AppTheme.Typography.monoCaption. The inline MiniPlayer title font is .footnote.weight(.semibold) and the inline clock font is .system(size: 11). <!-- [^a6b98-5] -->

## Dismiss Button

The MiniPlayer has a dismiss (×) button that pauses playback, clears the episode from the mini player (state.episode = nil), and marks the episode as played via store.markEpisodePlayed, producing the same effect as swiping to remove in Continue Listening. The button uses an xmark symbol with .callout.weight(.semibold) font, .secondary foreground, a 36pt label frame inside a 44pt hit area, .pressable button style, and an accessibility label of 'Dismiss'. The dismissCurrentEpisode() method triggers Haptics.warning() before pausing and clearing the episode. <!-- [^a6b98-6] -->

## Progress Bar

The 3px accent-colored progress bar overlay on the expanded MiniPlayer was removed as dead code because the glass material swallows it visually. The progressFraction computed property and progressLine property were also removed from MiniPlayerView as dead code along with the progress bar. <!-- [^a6b98-7] -->

## Transitions

The glassEffectID('player.surface') is used on the expanded MiniPlayer content to link it to the full-player morph transition. <!-- [^a6b98-8] -->

## Skip Glyph

Skip glyph logic must be centralized to eliminate duplication between PlayerControlsView and MiniPlayerView. <!-- [^rollo-54] -->
