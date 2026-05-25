# Target Architecture

## Layered model (post-migration)

```
        +---------------------------------------+
        |          SwiftUI Views                |   pure render
        | App/Sources/Features/** copied here   |   no decisions
        | as ios/Podcast/Podcast/Features/**    |
        +-----------------+---------------------+
                          | @EnvironmentObject model
                          v
        +---------------------------------------+
        |  KernelModel (Swift ObservableObject) |   thin shell
        |  - snapshot: PodcastUpdate            |   computed accessors only
        |  - dispatch helpers (no logic)        |
        +-----------------+---------------------+
                          | raw C FFI
                          v
        +---------------------------------------+
        |  Bridge layer (Swift)                 |   FFI marshalling
        |  KernelBridge/{handle,callbacks,      |   never decides
        |    decode,dispatch,types}.swift       |   each file < 300 LOC
        +-----------------+---------------------+
                          | nmp_app_*
                          v
        +---------------------------------------+
        |   nmp-app-podcast (Rust staticlib)    |
        |   - register_defaults from template   |
        |   - register podcast modules          |
        +-----------------+---------------------+
            |             |                |
            v             v                v
        nmp-core    nmp-nipNN ...    capability seams
        kernel +    Nostr protocol   (audio, http,
        router +    crates           keychain, stt,
        signers +                    tts, vector,
        store +                      download,
        EventStore                   notifications,
                                     spotlight,
                                     carplay-state)
                          ^
                          | JSON request envelopes
                          v
        +---------------------------------------+
        |  Native Capability Executors (Swift)  |
        |  one per namespace, all D7-compliant  |
        +---------------------------------------+
```

## Ownership table

| Concern | Owner | Notes |
|---|---|---|
| Domain types (Episode, Podcast, Chapter) | Rust (`podcast-core`) | D4 single writer. |
| State (AppState) | Rust kernel | Swift `KernelModel.snapshot` is a Decodable copy. |
| Persistence | Rust (`nmp-store` LMDB + per-store migrations) | See [`06-cross-cutting.md`](06-cross-cutting.md). |
| Nostr (relays, signing, NIPs) | Rust (`nmp-core` + NIP crates) | Outbox automatic. |
| RSS parsing, OPML I/O | Rust (`podcast-feeds`) | Streaming parser ported. |
| Audio playback | Swift executor only | AVPlayer driven via `nmp.audio.capability`. |
| Background download | Swift executor only | `URLSession` background driven via `nmp.download.capability`. |
| Transcription | Rust orchestrates, Swift fulfills | One adapter per provider under `Capabilities/Stt/`. |
| Vector / RAG | Rust orchestrates, Swift executes SQL | `nmp.vector.capability` wraps sqlite-vec. |
| Wiki generation | Rust (`podcast-knowledge`) | LLM HTTP via `nmp.http.capability`. |
| Agent loop, tools | Rust (`podcast-agent-core` + provider crates) | Token streaming flows back via snapshots. |
| Voice (STT + TTS + barge-in) | Rust decides, Swift streams audio | Audio bytes through capability. |
| Briefing composition | Rust (`podcast-briefings`) | Composition + stitching policy in Rust. |
| Settings (user prefs) | Rust kernel | DomainModule + ViewModule. |
| BYOK credentials | Rust kernel knows shape; Swift Keychain holds secret | Capability returns secret on demand. |
| UI rendering | Swift only | No `if`s about app behavior. |
| CarPlay templates | Swift renders, Rust pushes state | `nmp.carplay.capability` (write-back). |
| Widgets / Live Activity | Swift renders from App Group snapshot | Snapshot file maintained by Rust. |
| Push notifications | Rust decides cadence | `nmp.notifications.capability`. |
| Spotlight indexing | Rust decides what to index | iOS-only capability. |
| Handoff | Rust composes activity, Swift broadcasts | Capability surface. |
| Deep links | Rust parses, dispatches actions | `URL → action` mapping in Rust. |

## Dispatch / reconcile cycle (verified against Chirp)

1. User taps "play episode" → `EpisodeRowView` calls
   `model.playEpisode(episodeID)`.
2. `KernelModel.playEpisode` calls
   `dispatchAction(namespace: "podcast.player", body: {episode_id, verb})`.
3. FFI hands JSON to Rust actor; player domain module + audio executor
   are invoked.
4. Rust calls `nmp.audio.capability` with a `Load{url,position}` request.
5. Swift's `AudioCapability` loads `AVPlayer`, starts buffering, reports
   `{ status: "ready", position_ms: 0 }` back via correlation id.
6. Rust transitions `PlayerProjection` from `Idle` → `Loading(id)` →
   `Playing(id, pos)`.
7. Next snapshot tick: `PodcastUpdate.nowPlaying` is fresh; Swift
   re-renders Now Playing screen and Mini-player.
8. Position events from capability arrive inside ticks → progress bar
   updates smoothly.

Per D6, no error throws across FFI. A failure surfaces as
`PodcastUpdate.toasts: [Toast { message: "..." }]` that the Swift
toast layer renders.

## Snapshot cadence

- Default kernel emit rate: matches Chirp (≈4 Hz initially; verify
  against `nmp-core/src/actor/tick.rs` at M0).
- Agent streaming tokens: target ≈30 Hz. **Verify** the per-view emit
  rate is supported by `nmp-core` at the time M7 starts. If it's not,
  M7 is gated on a prerequisite NMP backlog item: extend the tick loop
  with a per-view override. Do not ship a Swift-side debounce.
- Position events from audio capability: throttled in the capability
  to ≤4 Hz so they don't outpace the kernel tick.

## Native code limited to two roles

1. **Render** — translate Rust-produced snapshot fields into UI.
2. **Execute capabilities** — call OS APIs and report raw results back
   to Rust. Never decide policy; never retry; never cache.

Everything else — state, business rules, derived data, routing,
recovery, protocol — is Rust.

## How a new platform plugs in

After M12, adding Android (Compose) or web (React + wasm):
1. Link `apps/podcast/nmp-app-podcast` as cdylib (Android/web) or rlib
   (desktop).
2. Implement each capability namespace listed in
   [`03-capabilities.md`](03-capabilities.md) using the platform's OS
   APIs.
3. Translate each SwiftUI view in `ios/Podcast/Podcast/Features/` into
   the platform's view system, binding to the same `PodcastUpdate`
   snapshot schema.

No Rust business logic is duplicated. The capability ADRs (see
[`03-capabilities.md`](03-capabilities.md)) include Android/web
acceptance criteria.

## Foundation gate (codex review finding)

Codex flagged that several NMP substrate APIs the original plan
referenced (`DomainModule`, `ViewModule`, `IdentityModule`) are not yet
implemented in `nmp-core`. The shipped substrate is `ActionModule`,
`CapabilityModule`, `DomainMigration`, and the `KernelEventObserver`
fan-out.

Decision: **the migration uses the shipped substrate**. We don't wait
for v2 typed-module runtime. Specifically:
- "DomainModule" in this plan means: a Rust type that owns state,
  receives `KernelEventObserver` callbacks, and exposes a projection
  field on the snapshot. It's not a named trait until NMP lands one.
- "ViewModule" means: a projection struct serialized as a snapshot
  field, kept fresh by an observer.
- "IdentityModule" means: existing `nmp-signers` integration.

If NMP later lands the v2 typed-module runtime, the migration adopts
it via a refactor PR — the public snapshot fields stay stable, only
the internal wiring changes.

This decision blocks M0 until validated against current NMP code.

## Reference: Chirp's iOS layout (the model to mirror)

```
ios/Chirp/Chirp/
├── App/
│   ├── ChirpApp.swift              57 LOC — @main, scenePhase
│   └── RootShell.swift            176 LOC — tabs, toast overlay
├── Bridge/                                — 4.5K LOC total
│   ├── KernelBridge.swift        1895 LOC (over the limit — Chirp debt)
│   ├── KernelModel.swift          640 LOC
│   └── (smaller bridges per feature)
├── Capabilities/
│   ├── ChirpCapabilities.swift     82 LOC (dispatcher)
│   ├── KeychainCapability.swift   282 LOC
│   └── HttpCapability.swift       269 LOC
├── Components/                            — reusable UI atoms
├── Features/                              — one file per screen
└── Theme/                                 — design tokens
```

Podcast mirrors this. Bridge files split into multiple <300 LOC files
from M0; we do not inherit Chirp's KernelBridge.swift LOC debt.

## Reference: Chirp's Rust layout

```
apps/chirp/nmp-app-chirp/
├── Cargo.toml                            — crate-type staticlib+rlib
└── src/
    ├── lib.rs                            — ~50 LOC re-exports
    └── ffi/
        ├── mod.rs
        ├── register.rs                   — entry point
        ├── handle.rs                     — opaque pointer
        ├── snapshot.rs                   — snapshot serialization
        └── actions.rs                    — app-specific actions
```

`nmp-app-podcast` follows the same layout. See [`02-crates.md`](02-crates.md).
