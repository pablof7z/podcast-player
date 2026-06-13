---
type: episode-card
date: 2026-06-08
session: 7e35e451-81d2-4832-8c6e-34d44fc29e12
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7e35e451-81d2-4832-8c6e-34d44fc29e12.jsonl
salience: root-cause
status: active
subjects:
  - apple-native-stt
  - speech-analyzer
  - on-device-transcription
supersedes: []
related_claims: []
source_lines:
  - 2804-2804
  - 2954-2966
  - 2979-2987
  - 3052-3056
  - 3080-3106
captured_at: 2026-06-12T13:35:49Z
---

# Episode: Apple on-device STT hung forever: SpeechAnalyzer never finalized

## Prior State

AppleNativeSTTClient.transcribe() called analyzer.analyzeSequence(from:) and then waited on transcriber.results in a for-try-await loop, with a comment claiming the stream ends naturally when analysis completes — but SpeechAnalyzer's results AsyncSequence never terminates without an explicit finalize call

## Trigger

User tested 'Retry with Apple on device' on physical iPhone after #351 fixed the path; saw 'transcription started' but it hung for 10+ minutes with no completion or failure — episode stuck at .transcribing indefinitely

## Decision

After analyzeSequence returns, call analyzer.finalizeAndFinishThroughEndOfInput() to flush remaining results and close the stream; restructured to drain results concurrently in a child task so finalization happens after audio is fully consumed

## Consequences

- On-device transcription now completes instead of hanging forever
- This bug was dormant because the download path mismatch prevented this code from ever executing before
- The prior crash-fix (1d40884a) removed double-driving but left the stream unterminated — the real fix required both no double-drive AND explicit finalization

## Open Tail

- Pending physical-device verification — user has been asked to test the fixed build on their iPhone before PR is opened

## Evidence

- transcript lines 2804-2804
- transcript lines 2954-2966
- transcript lines 2979-2987
- transcript lines 3052-3056
- transcript lines 3080-3106

