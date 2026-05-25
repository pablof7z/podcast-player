# M3 — Audio capability

**Status:** unclaimed
**Scale:** M
**Depends on:** M2
**Blocks:** M4, M7, M9, M11
**Parallel work units:** 5

---

## Scope

`nmp.audio.capability` lands as a pure AVPlayer driver. Player state
machine (load, play, pause, seek, rate, sleep timer, end-of-episode,
chapter advance) moves to Rust. PlayerView, Mini-player, Now Playing
UI render unchanged from `now_playing` projection.

Sonnet flagged `PlaybackState.swift` (497 LOC) as having business
logic. Split per [`../05-migration-map.md`](../05-migration-map.md).

Also: `AutoSnipController.swift` and clip composers move to Rust.

---

## Pre-flight

- [ ] M2 exit green.
- [ ] **API audit:** confirm `nmp-core::capability::audio` module
      exists (M0 BACKLOG entry `cap-audio` landed).
- [ ] Confirm second-platform Android stub from M2.F still builds.

---

## Parallel work units

### Unit M3.A — `nmp.audio.capability` Rust + ADR

**Owner:** _(unclaimed)_

**Tasks:**
- [ ] Land `nmp-core::capability::audio` (request/response/event enums
      per [`../03-capabilities.md`](../03-capabilities.md) §5.1).
- [ ] ADR `nostrmultiplatform/docs/decisions/00NN-cap-audio.md`.
- [ ] Android stub: ExoPlayer wiring sketch (signatures only).
- [ ] Doctrine-lint test asserts no policy in capability layer.

**Quality gates:**
- [ ] `cargo test -p nmp-testing` green.
- [ ] ADR reviewed by orchestrator.

### Unit M3.B — `podcast-core::player` projection

**Owner:** _(unclaimed)_

**Tasks:**
- [ ] `PlayerState` (Idle/Loading/Playing/Paused/Buffering/Ended/Failed).
- [ ] Queue management (next/prev, history).
- [ ] Sleep timer (Off / Duration / EndOfEpisode + fade-out flag) —
      replaces `PlaybackState.swift` logic.
- [ ] End-of-episode policy: auto-advance to next in triage queue;
      mark current as completed; record audit event.
- [ ] Chapter advance (when current position crosses chapter
      boundary).
- [ ] Position debounce + persistence (every 5s or on pause).
- [ ] Long-episode + partial-file seek handling (R8): expose
      `chapter_seekable: bool` based on buffer progress.

**Quality gates:**
- [ ] Unit tests cover every state transition with mocked capability
      events.
- [ ] No `unwrap` panics on malformed events (D6).

### Unit M3.C — iOS AudioCapability executor

**Owner:** _(unclaimed)_
**Worktree:** `podcast-worktree-m3c/`

**Tasks:**
- [ ] Create `Capabilities/AudioCapability.swift`,
      `AudioCapability+Session.swift`,
      `AudioCapability+NowPlaying.swift`,
      `AudioCapability+RemoteCommands.swift`.
- [ ] Move AVPlayer wiring from legacy `Audio/AudioEngine.swift` to
      capability. **No decisions remain in Swift.**
- [ ] Position observer at 4 Hz throttle.
- [ ] AVAudioSession routing (category .podcastPlayback, options
      handled per request).
- [ ] MPRemoteCommandCenter wiring (commands feed back as
      `RemoteCommand` events).
- [ ] MPNowPlayingInfoCenter wiring (driven by `SetMetadata` request).
- [ ] Sleep timer execution (driven by `SetSleepTimer` request).

**Quality gates:**
- [ ] Manual: play episode, pause, scrub, rate change, sleep timer,
      AirPods play/pause control work.
- [ ] Lint: no `if`/`switch` deciding behavior; only AVFoundation
      calls.

### Unit M3.D — UI migration: Player, EpisodeDetail, Mini-player

**Owner:** _(unclaimed)_

Files to migrate:
- `App/Sources/Features/Player/*.swift` (incl. `PlaybackState.swift`
  split — class excised; the View struct remains).
- `App/Sources/Features/Player/VoiceNote/*.swift` (placeholder; voice
  features land in M8).
- `App/Sources/Features/Player/AutoSnip/AutoSnipController.swift` —
  split (class excised → `podcast-core::clip::autosnip`).
- `App/Sources/Features/EpisodeDetail/*.swift`.
- `App/Sources/Features/EpisodeDetail/Clip/*.swift`.
- The split files: `ClipAudioComposer.swift`,
  `ClipVideoComposer.swift` — classes excised → Rust ports.

**Tasks:**
- [ ] Run tooling: copy → split → token-swap → fidelity verify.
- [ ] Mini-player accessory in `RootShell` reads `model.snapshot?.now_playing`.
- [ ] Capture/match goldens for Now Playing, Mini-player collapsed,
      Mini-player expanded, Episode Detail, Chapter rail, Sleep
      sheet, Clip Composer.

**Quality gates:**
- [ ] All snapshot tests match legacy goldens.
- [ ] No business logic remains in any copied file.

### Unit M3.E — Clip pipeline (Rust ports + video capability defer)

**Owner:** _(unclaimed)_

**Tasks:**
- [ ] Port `ClipBoundaryResolver.swift` →
      `podcast-core::clip::resolver`.
- [ ] Port `ClipExporter.swift` (the planning + metadata side) →
      `podcast-core::clip::export`.
- [ ] Decide on `nmp.video.capability` for clip-video rendering: ship
      now, defer to v1.1, or use AVAssetExport via a higher-level
      audio-capability extension? Default plan: file BACKLOG
      `cap-video` and defer video-clip share to v1.1 (clip audio
      share works in M3 via existing audio capability).
- [ ] Audio clip share works end-to-end (mp3 cut + share sheet).

**Quality gates:**
- [ ] Clip-audio export tested with a 30s clip.
- [ ] If video deferred, ensure UI shows "Audio clip" only and BACKLOG
      entry filed.

---

## Sequential integration

- [ ] Merge M3.A (capability spec) first.
- [ ] Merge M3.B (player projection) — depends on capability spec.
- [ ] Merge M3.C (iOS executor) — depends on capability spec.
- [ ] Merge M3.D (UI) — depends on projection.
- [ ] Merge M3.E (clips).
- [ ] Live test: play an episode for 5 minutes, scrub, pause, AirPods
      controls, sleep timer.
- [ ] **Second-platform Android stub:** ExoPlayer executor returns
      `Status` for `QueryStatus` request. Compose Player view binds
      to same snapshot. Doesn't need to actually play audio in M3 —
      just prove the capability boundary is portable.

---

## Exit checklist

- [ ] All units merged.
- [ ] PlayerView, Mini-player, Now Playing render identical to legacy.
- [ ] Scrub, skip, rate, sleep timer all work.
- [ ] Lock-screen + AirPods controls work.
- [ ] CarPlay Now Playing template still works (interim — full CarPlay
      in M11).
- [ ] Audio clip share works.
- [ ] Long episodes: per-chapter buffer state visible (R8).
- [ ] **Swift files deleted at end:**
  - `App/Sources/Audio/*.swift` (all 5 — replaced by capability)
  - `App/Sources/Features/Player/PlaybackState.swift` (class part — file kept; View struct preserved)
  - `App/Sources/Features/Player/AutoSnip/AutoSnipController.swift` (class part)
  - `App/Sources/Features/EpisodeDetail/Clip/Share/{ClipAudioComposer,ClipVideoComposer}.swift` (classes; if video deferred, ViewModel stub stays — flagged)
  - `App/Sources/Services/{ClipBoundaryResolver,ClipExporter}.swift`
- [ ] Whats-new entry (skip — internal).
- [ ] M4 unblocked.

## Hand-off to M4

M4 can rely on:
- `now_playing.position_ms` ticks smoothly.
- The player decides when to enqueue a new episode; M4 fulfills
  downloads behind it.
