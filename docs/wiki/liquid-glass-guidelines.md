---
title: Liquid Glass Guidelines
slug: liquid-glass-guidelines
topic: ui-components
summary: Toolbar items in navigation bars must not use explicit `.buttonStyle(.glass)` or `.buttonBorderShape(.circle)`, as iOS 26 automatically applies the correct liqu
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:513924f8-3b98-47b0-a84a-38086416581a
  - session:9692d124-a1a0-411c-91f9-9d6ebc0b29b1
  - session:a6b98d9b-32b6-49e0-9bda-3204ca8808bb
  - session:a42285c2-863e-42d1-a433-e7bf25bcfc21
  - session:rollout-2026-05-10T20-50-50-019e1303-6619-7020-b335-29bdce14a986
  - session:rollout-2026-05-11T08-59-24-019e159e-6c26-72c1-8860-3adc6e4c5039
---

# Liquid Glass Guidelines

## Navigation Bar Toolbar Items

Toolbar items in navigation bars must not use explicit `.buttonStyle(.glass)` or `.buttonBorderShape(.circle)`, as iOS 26 automatically applies the correct liquid glass treatment to toolbar items and manual styling creates a double-glass effect. Navigation bar toolbar buttons across the app (including RootView, AgentChatView, and FeedbackView) must not wrap items in a `GlassEffectContainer` inside a `ToolbarItem`. <!-- [^51392-3] -->


All settings screens use a top-right navigation bar toolbar button (.toolbar { ToolbarItem(placement: .navigationBarTrailing) }) for Save actions, not inline Button rows inside the Form body. <!-- [^9692d-3] -->

The iOS 26 tab-bar minimization modifier on the root TabView must be removed to prevent the keyboard from dismissing immediately when focusing text inputs. <!-- [^rollo-105] -->
## Icon Selection

The home tab toolbar uses a bare `plus` symbol rather than `plus.circle` to avoid a double-circle rendering under iOS 26 liquid glass. <!-- [^51392-4] -->

## Settings Screen Save Actions

Destructive actions (Disconnect, Remove Endpoint, Reset to Default) remain inline in the form body rather than in the toolbar. Text fields in settings screens support onSubmit (keyboard return) as a complementary save trigger alongside the toolbar Save button. <!-- [^9692d-4] -->

## Expanded MiniPlayer

The expanded MiniPlayer container uses .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16)) as its sole background with no explicit Color, background(), or material. The expanded MiniPlayer body is wrapped in a GlassEffectContainer to allow button glass beads to merge with the surface glass on press. The content inside GlassEffectContainer uses .glassSurface(cornerRadius: AppTheme.Corner.lg) instead of the prior single .glassEffect() approach. <!-- [^a6b98-1] -->

Each transport button (play, skip, dismiss) uses .glassEffect(.regular.interactive(), in: .circle) on its label instead of the custom .pressable button style. <!-- [^a6b98-2] -->

## Design Tokens & Liquid Glass

The app uses a design token system via `AppTheme` (Spacing, Corner, Typography, Gradients) and `GlassEffectContainer`/`glassEffect`/`glassSurface` for Liquid Glass materials, using `Color.accentColor` instead of the non-existent `AppTheme.Tint.accent`. (Previously: The app uses a design token system via `AppTheme` (Spacing, Corner, Typography, Tint, Gradients) and `GlassEffectContainer`/`glassEffect`/`glassSurface` for Liquid Glass materials. <!--  -->, superseded — see agent-owned-podcasts.)

Tab-like segmented controls throughout the app use the LiquidGlassSegmentedPicker instead of plain .pickerStyle(.segmented) or custom toolbar text toggles. <!-- [^rollo-60] -->
