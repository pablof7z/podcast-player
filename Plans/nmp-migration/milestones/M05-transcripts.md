# M5 — Transcripts

**Status:** unclaimed
**Scale:** L
**Depends on:** M4
**Blocks:** M6, M7, M8
**Parallel work units:** 5

---

## Scope

`nmp.stt.capability` lands. `podcast-transcripts` crate orchestrates
multi-provider STT (publisher-supplied / Apple SpeechAnalyzer /
AssemblyAI / ElevenLabs Scribe / Whisper). TranscriptionQueue and
ingestion policy move to Rust. **No polling** — webhook/callback flow
for batch providers (R3).

Existing per-episode `TranscriptStore` JSON files migrated into
Rust-side store.

---

## Pre-flight

- [ ] M4 exit green.
- [ ] Confirm NMP BACKLOG `cap-stt` landed; ADR done.
- [ ] Confirm webhook-callback transport: either local HTTPS callback
      endpoint or push notification carrier. Decide here, record in
      ADR.

---

## Parallel work units

### Unit M5.A — `nmp.stt.capability` Rust + ADR

**Tasks:**
- [ ] Capability per [`../03-capabilities.md`](../03-capabilities.md)
      §5.4.
- [ ] No `BatchPollResult` polling variant. Replaced with
      `JobStarted{job_id}` + `JobComplete{result}` event delivered via
      provider callback.
- [ ] Android stub: Android SpeechRecognizer placeholder.

### Unit M5.B — `podcast-transcripts` crate

**Tasks:**
- [ ] Queue, provider router, parsers (VTT/SRT/JSON), chunker per
      [`../02-crates.md`](../02-crates.md).
- [ ] Provider selection policy: publisher transcript → Apple
      on-device → BYOK fallback chain.
- [ ] Chunking output drives RAG embedding in M6.

**Quality gates:**
- [ ] Parser fixtures match legacy output.
- [ ] Queue dedupes simultaneous requests for same episode.

### Unit M5.C — iOS STT adapters

**Tasks:**
- [ ] Per-provider adapters under `Capabilities/Stt/`:
      `AppleNativeAdapter.swift`, `AssemblyAIAdapter.swift`,
      `ElevenLabsAdapter.swift`, `WhisperAdapter.swift`.
- [ ] AssemblyAI/ElevenLabs: register local callback server (HTTPS
      with self-signed via app cert) OR use push-notification
      payload. No polling.
- [ ] Apple SpeechAnalyzer for on-device.

**Quality gates:**
- [ ] Each provider transcribes a 60s test clip end-to-end.
- [ ] D7 audit: no provider routing in any adapter.

### Unit M5.D — TranscriptStore migration

**Tasks:**
- [ ] One-shot migration reads existing per-episode JSON files via
      `nmp.legacy_io.capability` and writes into the new transcript
      store under `podcast-transcripts::queue::store`.

**Quality gates:**
- [ ] Idempotent; ≤30s on a 200-episode dataset.

### Unit M5.E — UI: Transcript view in Episode Detail, Settings → STT

**Tasks:**
- [ ] Files already migrated in M3 (EpisodeDetail); verify transcript
      view binds to `transcript_for_open_episode`.
- [ ] Settings → STT provider chooser binds to settings projection
      (no logic; just rendering options + dispatching update).

**Quality gates:**
- [ ] Goldens match.

---

## Sequential integration

- [ ] Merge in A → B → C → D → E order.
- [ ] Live test on at least one real episode per provider.

---

## Exit checklist

- [ ] Transcription works via every supported provider.
- [ ] On-device Apple STT works on iOS 26.
- [ ] No polling anywhere (lint catches `sleep` + `recv` patterns).
- [ ] Legacy transcripts visible without re-transcribing.
- [ ] **Swift files deleted:**
  - `App/Sources/Transcript/Transcript.swift`,
    `TranscriptionQueue.swift`, `Parsing/*`,
    `AppleSTT+TranscriptAdapter.swift`.
  - `App/Sources/Services/TranscriptIngestService.swift` +
    `+AutoIngest.swift` + `+Chunkable.swift`.
  - `App/Sources/Services/TranscriptStore.swift`.
  - `App/Sources/Services/ChaptersHydrationService.swift`.
- [ ] M6 unblocked.

## Hand-off to M6

M6 can rely on: transcripts ingested with provider metadata; chunks
produced.
