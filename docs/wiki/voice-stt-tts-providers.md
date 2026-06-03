---
title: Voice STT/TTS Providers
slug: voice-stt-tts-providers
summary: The default voice STT provider is apple_native, with key-based fallback to ElevenLabs or AssemblyAI.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-31
updated: 2026-06-02
verified: 2026-05-31
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:4c830774-3f88-48e6-ab2b-ccaa1a277e00
---

# Voice STT/TTS Providers

## Voice STT Providers

The default voice STT provider is apple_native, not elevenlabs_scribe, with a keyless fallback that downgrades cloud providers to native. The apple_native provider is the Apple Intelligence transcription provider, using SpeechTranscriber and SpeechAnalyzer from iOS 26 with no separate Apple Intelligence transcription API. It does not support speaker diarization and produces a flat transcript with no speaker IDs.

<!-- citations: [^14943-114] [^14943-129] [^4c830-2] -->
## Voice TTS Providers

Voice TTS checks the ElevenLabs voice_id and dispatches to the appropriate provider. <!-- [^14943-115] -->
