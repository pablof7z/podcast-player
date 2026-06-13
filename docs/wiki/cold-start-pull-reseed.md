---
title: Cold-Start Pull Re-Seed Insurance
slug: cold-start-pull-reseed
topic: data-persistence
summary: "Cold-start pull re-seed insurance uses a hasHydrated flag: the first pull uses >= for rev comparison, then strict > afterward; resetAndRestart resets the flag."
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-13
updated: 2026-06-13
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Cold-Start Pull Re-Seed Insurance

## Has-Hydrated Flag Logic

Cold-start pull re-seed insurance uses a hasHydrated flag: the first pull uses >= for rev comparison, then strict > afterward; resetAndRestart resets the flag. <!-- [^c1691-265] -->
