---
title: AssemblyAI STT
slug: assemblyai-stt
topic: stt-providers
summary: AssemblyAI is integrated as an STT provider using URL-based input, passing the episode enclosure URL directly to the API
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-11
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
---

# AssemblyAI STT

## AssemblyAI STT Integration

AssemblyAI is integrated as an STT provider using URL-based input, passing the episode enclosure URL directly to the API. The integration hardcodes `speaker_labels=true` and `language_detection=true` in requests. <!-- [^7f076-3] -->

Authentication uses a raw API key header (no Bearer prefix), with the key stored in Keychain via `AssemblyAICredentialStore`. <!-- [^7f076-4] -->

The `speech_models` field uses an ordered fallback list rather than a single model, defaulting to `universal-3-pro,universal-2`. <!-- [^7f076-5] -->
