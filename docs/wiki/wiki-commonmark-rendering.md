---
title: Wiki CommonMark Rendering
slug: wiki-commonmark-rendering
summary: A blank line must separate HTML citation comments from subsequent ATX headings in CommonMark-processed wiki files to ensure proper section rendering.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-02
updated: 2026-06-02
verified: 2026-06-02
compiled-from: conversation
sources:
  - session:8bfa1b91-b40c-44b3-acb9-245b36f4c841
---

# Wiki CommonMark Rendering

## HTML Citation Comments and ATX Headings

Wiki articles must have a blank line before ATX (##) headings for strict CommonMark compliance. A blank line must also separate HTML citation comments from subsequent ATX headings in CommonMark-processed wiki files to ensure proper section rendering.

<!-- citations: [^8bfa1-7] [^8bfa1-11] -->

## Staging and Commit Practices

All 18 new wiki articles referenced in _index.md must be staged in the same commit to avoid broken links. <!-- [^8bfa1-12] -->

## Content Permanence

Ephemeral, session-specific instructions (e.g., a TestFlight upload contingent on an unreleased fix) must not be committed as permanent wiki content. <!-- [^8bfa1-13] -->

## Deleted Article Handling

Deleted wiki articles must have a tombstone or redirect rather than leaving an empty page behind an index summary. <!-- [^8bfa1-14] -->
