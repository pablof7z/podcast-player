---
title: App Widget Build Alignment
slug: app-widget-build-alignment
topic: project-setup
summary: App and widget build numbers cannot diverge.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-10
updated: 2026-05-11
verified: 2026-05-10
compiled-from: conversation
sources:
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
  - session:rollout-2026-05-10T20-46-06-019e12ff-12ba-79d2-a14c-78a7ec6b0bfa
  - session:rollout-2026-05-11T09-10-31-019e15a8-991d-7890-957e-f45fb0ff5a7c
---

# App Widget Build Alignment

## Build Alignment

App and widget build numbers cannot diverge. App and widget version metadata must not drift during TestFlight. Version and build number must be set consistently for both the app and the widget, either via build settings for both targets or by updating both plists, without dirtying tracked files. TestFlight version stamping updates both app and widget plists and verifies archived app/widget metadata before export. The CI workflow APP_BUNDLE_ID must be set to io.f7z.podcast to match the app bundle ID in Project.swift, replacing the stale com.podcastr.podcastr default. The widget target needs its own PROVISIONING_PROFILE_SPECIFIER and export mapping for io.f7z.podcast.widget, or the project should simplify to automatic signing only. Manual TestFlight signing now expects both app and widget profiles when using manual provisioning. Widget signing must be documented and supported by set_github_secrets.sh, including widget provisioning profile upload via set_github_secrets.sh --widget-profile.

<!-- citations: [^rollo-39] [^rollo-40] [^rollo-56] [^rollo-129] -->
