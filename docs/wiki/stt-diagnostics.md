---
title: STT Diagnostics
slug: stt-diagnostics
topic: stt-providers
summary: The Diagnostics sheet offers a 'Retry with…' menu listing viable STT providers (Apple on-device when downloaded, ElevenLabs when credential configured, OpenRout
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-08
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:7e35e451-81d2-4832-8c6e-34d44fc29e12
---

# STT Diagnostics

## Retry Menu

The Diagnostics sheet offers a 'Retry with…' menu listing viable STT providers (Apple on-device when downloaded, ElevenLabs when credential configured, OpenRouter when credential configured, AssemblyAI when credential configured). <!-- [^7f076-10] -->


The Diagnostics sheet reloads events after a retry's ingest completes, even when the transcript state hasn't changed, so skip events become visible immediately. <!-- [^7e35e-11] -->
## Provider Dispatch

STT provider fallback policy moved to the Rust kernel; Swift dispatches stt_keys_present and reads effective_stt_provider from the snapshot projection. <!-- [^14943-24] -->

The Apple on-device STT hang was unreachable before PR #351 because the download path mismatch prevented the file-existence guard from passing, so on-device transcription had never actually started until now. <!-- [^7e35e-12] -->
