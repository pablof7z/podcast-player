---
title: AI Picks
slug: ai-picks
summary: AI picks are generated using build_listening_profile() from played, in-progress, and starred signals
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-01
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# AI Picks

## AI Picks

AI picks are generated using build_listening_profile() from played, in-progress, and starred signals. A cold-start degradation falls back to general interest when sufficient signal is unavailable. The auto_refresh_picks function is guarded by a picks_score_in_progress AtomicBool. <!-- [^14943-135] -->
