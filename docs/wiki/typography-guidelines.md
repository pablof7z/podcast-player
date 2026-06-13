---
title: Typography Guidelines
slug: typography-guidelines
topic: ui-components
summary: Serif fonts must never be used; all text must use SF (system font), with `UIFont.italicSystemFont` or `.italic()` for italics instead of any serif variant.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-25
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:rollout-2026-05-13T09-40-04-019e2010-60db-72b0-af0f-d40f44ca1989
  - session:rollout-2026-05-17T10-33-06-019e34da-5c83-7591-8bfc-850541168727
  - session:rollout-2026-05-25T12-53-43-019e5e8d-f919-7521-a540-9ca4b95f10ff
  - session:rollout-2026-05-25T12-53-46-019e5e8e-043d-7dc2-8171-2238de03d145
---

# Typography Guidelines

## Font Selection & Italic Usage

No serif fonts may be used anywhere in the app; `.serif` font design, `NewYork`, `NewYork-SemiboldItalic`, and any other serif typeface are prohibited. All text in the app must use SF (system font); for italic style, `UIFont.italicSystemFont` or `.italic()` modifier must be used, never a serif variant. This prohibition overrides the `docs/spec/product-spec/04-decisions-plan-risks-appendix.md` recommendation of New York serif typography.

<!-- citations: [^rollo-138] [^rollo-157] [^rollo-194] [^rollo-202] -->
