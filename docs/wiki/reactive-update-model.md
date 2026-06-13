---
title: Reactive Update Model
slug: reactive-update-model
topic: ui-components
summary: While the UI should generally avoid spinners for routine data fetches, legitimate loading indicators are appropriate for long-running operations such as LLM pro
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-02
updated: 2026-06-12
verified: 2026-06-02
compiled-from: conversation
sources:
  - session:8bfa1b91-b40c-44b3-acb9-245b36f4c841
---

# Reactive Update Model

## Loading Indicators

While the UI should generally avoid spinners for routine data fetches, legitimate loading indicators are appropriate for long-running operations such as LLM processing. Use contextual status indicators like `inbox_triage_in_progress` from the PodcastUpdate projection to drive the triage shimmer during background LLM triage, reserving them for cases where the user needs to know work is happening rather than applying a blanket 'no spinners ever' rule. (Previously: Use contextual status indicators like `triage_in_progress` to signal these asynchronous operations, reserving them for cases where the user needs to know work is happening in the background rather than applying a blanket 'no spinners ever' rule. <!--  -->, superseded — see home-featured-section.)
