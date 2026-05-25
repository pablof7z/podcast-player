# M8 — Voice (STT + TTS + barge-in)

**Status:** unclaimed
**Scale:** M
**Depends on:** M5, M7
**Blocks:** M9
**Parallel work units:** 4

---

## Scope

`nmp.tts.capability` lands. `podcast-voice` crate hosts the voice turn
loop. Barge-in detection runs in capability (raw events); cancellation
policy in Rust. Voice tab UI renders unchanged.

---

## Pre-flight

- [ ] M5 + M7 exits green.
- [ ] BACKLOG `cap-tts` ADR landed.
- [ ] R16 reconnection policy decided in `podcast-voice::manager` spec.

---

## Parallel work units

### Unit M8.A — `nmp.tts.capability`

**Tasks:**
- [ ] Capability per §5.5.
- [ ] Android stub: TextToSpeech sketch.

### Unit M8.B — `podcast-voice` crate

**Tasks:**
- [ ] VoiceSession state machine.
- [ ] Turn loop: STT (live mode) → tool-aware agent reply via
      `podcast-agent-core` → TTS streaming.
- [ ] Barge-in policy: capability emits voiced-segment events at
      ≈50 Hz; kernel cancels TTS on the next tick (sub-100ms).
- [ ] Caption projection.

**Quality gates:**
- [ ] Unit tests for state machine.

### Unit M8.C — iOS Voice capability executors

**Tasks:**
- [ ] `Capabilities/Tts/{ElevenLabsAdapter,AvSpeechAdapter}.swift`.
- [ ] `Capabilities/Voice/BargeInDetector.swift` (executor only —
      reports voiced-segment events; never decides cancellation).
- [ ] `Capabilities/Audio/AudioCapability+VoiceSession.swift` for
      mic capture (re-uses M3 audio capability with voice category).

**Quality gates:**
- [ ] Manual: open voice mode; barge in mid-utterance; TTS cuts
      within ≤150ms.

### Unit M8.D — iOS UI migration: Voice tab + VoiceNote sub-feature in Player

Files:
- `App/Sources/Features/Voice/*.swift`
- `App/Sources/Features/Player/VoiceNote/*.swift`

**Tasks:**
- [ ] Tooling: copy → token-swap.
- [ ] Bind to `voice_session` projection + caption.

**Quality gates:**
- [ ] Goldens match.

---

## Sequential integration

- [ ] Merge M8.A → M8.B → M8.C → M8.D.
- [ ] Live test on device: voice conversation with barge-in.

---

## Exit checklist

- [ ] Voice tab unchanged visually.
- [ ] Barge-in ≤ 150ms.
- [ ] Captions render real-time.
- [ ] Both ElevenLabs and AVSpeech fallback work.
- [ ] **Swift files deleted:**
  - `App/Sources/Voice/*.swift` (all 9 — replaced by capability +
    podcast-voice)
  - `App/Sources/Features/Player/VoiceNote/VoiceNoteRealtimeSTT.swift`
    (class part — file kept; View bytes preserved)
- [ ] M9 unblocked.

## Hand-off to M9

M9 can rely on: TTS streaming via capability + voice turn loop +
caption projection.
