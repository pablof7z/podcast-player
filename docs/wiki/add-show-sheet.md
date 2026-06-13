---
title: Add Show Sheet
slug: add-show-sheet
topic: ui-components
summary: "The Add Show sheet content fills the available space via frame(maxWidth: .infinity, maxHeight: .infinity) instead of leaving empty white space under the list."
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-11
updated: 2026-06-11
verified: 2026-06-11
compiled-from: conversation
sources:
  - session:ec1fb244-f19d-4667-8784-28bb26786eb9
  - session:rollout-2026-05-10T10-27-27-019e10c8-ab1d-7523-8825-9bb1a52e6aac
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
---

# Add Show Sheet

## Layout

The Add Show sheet content fills the available space via frame(maxWidth: .infinity, maxHeight: .infinity) instead of leaving empty white space under the list. <!-- [^ec1fb-1] -->

The VStack spacing between the segment picker and content is 0 for a flush layout. <!-- [^ec1fb-2] -->

## Segment Control

The Add Show sheet uses a proper segment control for switching between search, nostr,, from URL, and OPML. The "From URL" segment is wrapped in a ScrollView with keyboard dismiss. The OPML segment no longer uses a negative-padding hack. The add-show search field uses a UIKit-backed UITextField with bounded focus protection during active text entry to prevent the keyboard from dropping mid-input. OPML import is split from its nested NavigationStack chrome within Add Show, either by extracting OPMLImportContent separately or by presenting OPML as a distinct sheet instead of a segment.

<!-- citations: [^ec1fb-3] [^ec1fb-4] [^ec1fb-5] [^rollo-32] [^rollo-37] [^rollo-95] -->
