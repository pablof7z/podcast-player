---
title: Apple Native STT
slug: apple-native-stt
topic: stt-providers
summary: The apple_native provider (AppleNativeSTTClient.swift) serves as the Apple Intelligence transcription provider, using SpeechTranscriber and SpeechAnalyzer from
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-02
updated: 2026-06-10
verified: 2026-06-02
compiled-from: conversation
sources:
  - session:4c830774-3f88-48e6-ab2b-ccaa1a277e00
  - session:7e35e451-81d2-4832-8c6e-34d44fc29e12
  - session:09aca3ef-4576-4595-9ffa-9e4107d07a9a
  - session:681fa743-322c-4b1a-8e99-81a97aa1a904
---

# Apple Native STT

## Apple Native STT

The apple_native provider (AppleNativeSTTClient.swift) serves as the Apple Intelligence transcription provider, using SpeechTranscriber and SpeechAnalyzer from iOS 26 on the Apple Silicon NPU. It does not support speaker diarization and produces a flat transcript with no speaker IDs. The 'AI transcription fallback' toggle in Settings gates all automatic transcription including Apple Native STT, not just cloud providers. The client must call finalizeAndFinishThroughEndOfInput() after the file is consumed (typically from a child task that drains results) so that the transcriber results stream terminates and the transcription loop completes; otherwise the stream never closes and the loop hangs indefinitely. The Apple in-device transcription functionality is tested using XCTest on a physical iPhone device.

<!-- citations: [^4c830-2] [^7e35e-1] [^09aca-1] [^681fa-1] -->
