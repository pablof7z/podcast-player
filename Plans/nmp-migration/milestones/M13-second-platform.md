# M13 — Second-platform full proof

**Status:** unclaimed
**Scale:** L
**Depends on:** M12
**Blocks:** —
**Parallel work units:** 5

---

## Scope

Stand up the chosen second platform (Android Compose or web React) as
a near-feature-parity proof. The stub from M2.F covered the dispatch
+ snapshot + one capability. M13 extends to full surface: Home,
Library, Player, Discover, Wiki, Briefings, Search, Agent Chat,
Settings, Voice, Onboarding, Identity, Feedback.

No Rust business logic is duplicated. Only the rendering layer +
capability executors are written.

---

## Pre-flight

- [ ] M12 exit green.
- [ ] Choose platform (default Android Compose; alternative web
      React+wasm). Record decision in milestone notes.
- [ ] Confirm every capability in
      [`../03-capabilities.md`](../03-capabilities.md) has an Android
      (or web) implementation path documented in its ADR.

---

## Parallel work units

### Unit M13.A — Platform shell + bridge

**Tasks:**
- [ ] Android: cargo-ndk builds `libnmp_app_podcast.so` for arm64,
      armv7, x86_64. Compose Activity loads kernel via JNI.
- [ ] OR Web: wasm-bindgen output; Vite host loads `nmp_app_podcast.wasm`.
- [ ] Bridge: Kotlin/TS analog of `KernelBridge.swift`. ~1500 LOC
      maximum for Kotlin (per Sonnet review on realistic effort).

**Quality gates:**
- [ ] Kernel boots on real device or browser.
- [ ] Snapshot decoded.

### Unit M13.B — Capability executors

**Tasks:**
- [ ] Implement every capability from
      [`../03-capabilities.md`](../03-capabilities.md) for the chosen
      platform. iOS-only capabilities (CarPlay, Spotlight, Handoff,
      iCloud, Review) report `Unsupported`.
- [ ] Android: ExoPlayer (audio), WorkManager (download),
      SpeechRecognizer (STT) + AssemblyAI/ElevenLabs adapters,
      TextToSpeech (TTS), Keychain via Android KeyStore, sqlite-vec
      via Android SQLite.
- [ ] Web: HTMLMediaElement (audio), Service Worker (download),
      Web Speech API + provider adapters (STT), Web Speech (TTS),
      WebCrypto + IndexedDB (keychain analog), IndexedDB-vec.

**Quality gates:**
- [ ] Each capability passes its acceptance test.

### Unit M13.C — UI translation (Home + Library + Player)

**Tasks:**
- [ ] Compose / React versions of the three core surfaces.
- [ ] Bind to same `PodcastUpdate` snapshot fields.
- [ ] Visual style mirrors iOS where the platform's idioms allow;
      otherwise platform-native (this isn't a 1:1 pixel match — it's
      "same app, native idioms").

**Quality gates:**
- [ ] Three screens render with real subscribed-podcasts data.

### Unit M13.D — UI translation (Agent + Discover + Wiki + Settings)

**Tasks:**
- [ ] Compose / React versions of remaining major surfaces.
- [ ] Live agent chat with streaming tokens works.

**Quality gates:**
- [ ] Manual: full agent conversation, NIP-46 sign-in, library +
      playback all work on second platform.

### Unit M13.E — Cross-platform consistency tests

**Tasks:**
- [ ] Test harness that runs the same action sequence through iOS
      and the second platform and asserts byte-identical
      `PodcastUpdate` JSON.
- [ ] Wire into CI.

**Quality gates:**
- [ ] Test green for at least 10 scripted scenarios (sign in, subscribe,
      play, transcribe, search, agent turn, etc.).

---

## Sequential integration

- [ ] Merge A → B → C → D → E.
- [ ] Ship second-platform alpha build.

---

## Exit checklist

- [ ] Second-platform build ships with all major surfaces functional.
- [ ] Cross-platform consistency tests green.
- [ ] No Rust business logic was duplicated (verified by repo audit —
      no `class .*Service`-equivalents in Kotlin/TS).
- [ ] Whats-new entry: "Podcastr is now available on
      [Android|web]. Same engine, native experience."
- [ ] The "near-trivial new platform" promise is empirically verified
      and documented (post-mortem in
      `Plans/nmp-migration/M13-post-mortem.md` with actual effort
      vs. estimate).

## Migration complete

Once M13 ships, the original migration goal is met:
- UI byte-identical (iOS) — verified by goldens.
- All business logic in Rust — verified by lints.
- New platform trivial — verified by M13.
- Zero hacks — verified by doctrine lint + codex review every PR.

Further milestones (M14+) would be product feature work, not
migration. They go into normal Pod0 planning (`docs/plan.md`,
`docs/BACKLOG.md`, or linked files under `docs/plan/`) and NMP planning,
not this directory.
