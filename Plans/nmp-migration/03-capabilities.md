# Capability bridges

Each capability namespace is defined by request enum, response/event
enum, native skeleton, Rust contract. iOS implementations are described
inline; Android/web sketches are required acceptance criteria for the
capability's ADR (per Codex review — "near-trivial new platform"
requires each capability to be designed multi-platform up front).

All capabilities live as Rust modules under
`nmp-core::capability::<name>` (extending Chirp's existing pattern for
`keyring` and `http`).

## Authoring rule

Each capability lands with:
- A request/response/event enum (serde-tagged).
- A doctrine-lint test under `crates/nmp-testing/tests/doctrine_lint_smoke.rs`
  asserting D7 (no policy in native).
- An ADR at `nostrmultiplatform/docs/decisions/00NN-cap-<name>.md`.
- An Android implementation **stub** (signature in Kotlin only, no impl
  required for v1) committed alongside the iOS impl. This is the
  contract for Codex review's "second platform proof must happen
  early" finding.

---

## 5.1 nmp.audio.capability

**Purpose:** media playback. iOS: AVPlayer. Android: ExoPlayer. Web:
HTMLMediaElement.

**Request:**
```rust
enum AudioRequest {
    Load { episode_id, url, position_ms, start_chapter },
    Play, Pause,
    Seek { position_ms },
    SetRate { rate },
    SetSleepTimer { kind: Off|EndOfEpisode|Duration{ms}, fade_out },
    StartObservers,
    Stop,
    SetMetadata { now_playing: NowPlayingMetadata },
    QueryStatus,
}
```

**Response (one-shot):**
- `Ok`, `Loaded{duration_ms}`, `Failed{reason}`,
  `Status{state,position_ms,rate}`, `Unsupported`.

**Events (multi-shot):**
- `Position{episode_id, position_ms}` — throttled to ≤4 Hz.
- `State{episode_id, state}` — Idle/Loading/Playing/Paused/Buffering/Failed.
- `BufferingChange{stalled,likely_to_keep_up}`.
- `Ended{episode_id}`.
- `RemoteCommand{command}` — play/pause/skip-fwd/skip-back/rate.
- `SleepFired`.
- `InterruptionBegan` / `InterruptionEnded`.
- `RouteChanged{route}` — bluetooth, speaker, etc.

**iOS executor:** `Capabilities/AudioCapability.swift`. Owns one
`AVPlayer` + `AVAudioSession` driver. Never decides what to play next on
`Ended` — emits the event and waits. End-of-queue logic lives in
`podcast-core::player`.

**Android sketch:** ExoPlayer with `Player.Listener`. MediaSession
attached for system controls. Audio focus handled in the capability;
focus loss → emit `InterruptionBegan`.

**Web sketch:** `<audio>` element with timeupdate event listener,
Media Session API for browser/OS integration.

## 5.2 nmp.download.capability

**Purpose:** background downloads.

**Request:**
- `Start { task_id, url, dest_path, etag, if_modified_since }`
- `Cancel { task_id }`
- `Query { task_id }`, `QueryAll`
- `Pause { task_id }`, `Resume { task_id }` (where supported)

**Response/events:**
- `Progress { bytes_done, total }` (≤1 Hz).
- `Completed { path, etag, last_modified, size }`.
- `Failed { reason }`.
- `Paused { resume_token? }` — resume tokens persisted in Rust.

**iOS:** background `URLSession` (preserve existing session identifier
for migration). Delegates re-register on launch.

**Android sketch:** WorkManager with foreground-service for active
downloads; scoped storage for `dest_path`.

**Web sketch:** Service Worker + fetch with Range header for resume.

## 5.3 nmp.notifications.capability

**Purpose:** local schedule + push token.

**Request:**
- `RequestPermission`
- `ScheduleLocal { id, title, body, when, payload }`
- `CancelLocal { id }`, `CancelAllLocal`
- `RegisterPushToken`
- `Badge { count }`

**Response/events:** permission status, token, success/fail.

**iOS:** UNUserNotificationCenter. Token via
`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.

**Android sketch:** NotificationManager + FCM via `FirebaseMessaging`.

**Web sketch:** Notifications API + Web Push.

## 5.4 nmp.stt.capability

**Purpose:** speech-to-text multi-provider seam.

**Providers:** `apple_native` (iOS 26 SpeechAnalyzer), `assemblyai`,
`elevenlabs_scribe`, `whisper_openrouter`.

**Request:**
```rust
enum SttRequest {
    BatchTranscribe { provider, audio_url, language, episode_id, webhook_url },
    BatchStatus { provider, job_id },
    StreamOpen { provider, session_id, language, mode: Live|Voice },
    StreamSendAudio { session_id, pcm },
    StreamFinalize { session_id },
    StreamClose { session_id },
}
```

**Events:** `PartialText`, `FinalText`, `SpeakerTurn`, `Error`,
`JobStarted{job_id}`, `JobComplete{result}` (delivered when AssemblyAI/
ElevenLabs webhook fires).

**No polling.** AssemblyAI/ElevenLabs batch flows deliver completion via
webhook. The capability opens a local HTTPS callback endpoint (or, on
constrained platforms, uses push notification carrier). The provider
calls back; the capability emits `JobComplete`. (Sonnet review caught
that the original plan endorsed polling. That is forbidden.)

**iOS:** per-provider adapter under `Capabilities/Stt/`. Native SDK
where unavoidable; otherwise pure HTTP/WS via `nmp.http.capability`.

**Provider routing** (which provider to use, fallback, override) lives
in Rust (`podcast-transcripts::providers::router`).

## 5.5 nmp.tts.capability

**Purpose:** streaming text-to-speech.

**Providers:** `elevenlabs_flash25` (WebSocket streaming),
`apple_av_speech` (fallback).

**Request:**
- `Open { session_id, voice_id, provider, format }`
- `SendText { session_id, text, flush }`
- `Cancel { session_id }`, `Close { session_id }`
- `SynthesizeOneShot { text, voice_id, provider } -> bytes`

**Events:** `AudioChunk{bytes}`, `SessionEnded`, `Error`.

**iOS:** `Capabilities/Tts/{ElevenLabsAdapter, AvSpeechAdapter}.swift`.
Crossfade timing decided in Rust (`podcast-briefings::stitcher`); the
capability just streams.

## 5.6 nmp.vector.capability

**Purpose:** vector DB seam. iOS/Android: sqlite-vec via SQLite.
Web: IndexedDB-vec (per codex review, web support cannot be deferred
past M2/M3 if multiplatform triviality is real). Long term: pure-Rust
HNSW retires this capability.

**Request:** raw primitives only (no policy):
- `OpenIndex { name, dim }`
- `Upsert { name, chunks: Vec<ChunkRecord> }`
- `Delete { name, ids }`
- `KnnSearch { name, vector, k, scope_filter }` — raw KNN.
- `BM25Search { name, query, k, scope_filter }` — raw FTS.
- `Compact { name }`

**No `QueryHybrid`** in the capability (Codex review caught that hybrid
ranking is policy and belongs in Rust). RRF, reranking, query expansion
all live in `podcast-knowledge::rag`.

**iOS:** `Capabilities/VectorCapability.swift` wraps existing
sqlite-vec actor.

## 5.7 nmp.spotlight.capability (iOS-only)

**Purpose:** Spotlight indexing. iOS-only.

**Request:** `Index{items}`, `Delete{ids}`.

**Other platforms:** capability reports `Unsupported`. Rust handles
gracefully (no-op).

**iOS:** `CSSearchableIndex` wrapper.

## 5.8 nmp.carplay.capability (iOS-only)

**Purpose:** CarPlay state push. CarPlay templates don't observe
SwiftUI reactivity; the capability subscribes to the kernel snapshot
via Combine and rebuilds templates on `carPlay.rev` advance.

**Request:** `Refresh{state: CarPlayState}` — templates (Now Playing,
Listen Now, Shows, Downloads, Search). The full template tree is
described in `CarPlayState` so the capability is a renderer.

**Events:** user-initiated taps come back as `Selected{action}` which
the kernel processes as a normal action dispatch.

## 5.9 nmp.http.capability (already in Chirp; widen)

Reuse existing Chirp implementation. Widen to support:
- Range requests (partial audio fetch).
- Streaming download (large transcription uploads).
- Multi-part form upload (Blossom in M10).
- SSE streaming (LLM completion).
- WebSocket lifecycle (TTS streaming, feedback relay, peer-agent relay).

## 5.10 nmp.keychain.capability (already in Chirp)

Copy verbatim from Chirp's `KeychainCapability.swift`. Add namespaces
for BYOK secret slots (`pcst.byok.openrouter`, `pcst.byok.elevenlabs`,
etc.).

## 5.11 nmp.video.capability (M3 deferred / BACKLOG)

For `ClipVideoComposer` (AVAssetExport on iOS, ffmpeg-wasm on web).
File NMP BACKLOG entry at M3 start; ship if M3 effort permits else
defer to v1.1.

## 5.12 nmp.handoff.capability (iOS-only)

`NSUserActivity` broadcast. Rust composes the activity payload; the
capability calls `becomeCurrent()`.

## 5.13 nmp.icloud.capability (iOS-only)

iCloud KV-store mirror for cross-device settings sync. Decisions
(what to sync, conflict resolution) in Rust.

## 5.14 nmp.review.capability (iOS-only)

`SKStoreReviewController.requestReview(in: scene)` executor. Decision
when to request lives in Rust (`podcast-core::review_prompt`).

## 5.15 nmp.data_export.capability

File-write executor (`Capabilities/DataExportCapability.swift`).
JSON/CSV/zip blob bytes come from Rust; capability writes to user-picked
location.

---

## Cross-cutting capability rules

- **D7 audit**: every capability's ADR must include a "what would be a
  D7 violation" section listing decisions native must not make.
- **Correlation IDs**: every request carries one; responses cite it.
- **Idempotence**: re-issuing a `Load`/`Start` with the same id is a
  no-op if already in progress.
- **Cancellation**: every request type supports a corresponding cancel
  variant; cancellations are best-effort and idempotent.
- **Error envelopes**: failures are `Failed{reason: String}` data, not
  thrown errors (D6).
- **Unsupported**: capabilities not available on a platform return
  `Unsupported` rather than panicking.
- **Threading**: capability callbacks may arrive on any thread; the
  capability marshals to the right queue. Rust treats all callbacks
  as untrusted async input.
- **D15**: any Swift closure passed across FFI is wrapped in
  `catch_unwind` on the Rust side.
