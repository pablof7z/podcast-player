---
title: Voice Conversation Shutdown
slug: voice-conversation-shutdown
summary: Voice conversation shutdown uses abort+join of in-flight handles called from nmp_app_podcast_unregister before nmp_app_free, with a shutting_down AtomicBool gua
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

# Voice Conversation Shutdown

## Voice Conversation Shutdown

Voice conversation shutdown uses abort+join of in-flight handles called from nmp_app_podcast_unregister before nmp_app_free, with a shutting_down AtomicBool guard before dereferencing the app pointer. <!-- [^14943-157] -->
