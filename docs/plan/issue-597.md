# Issue 597 — Epic A: Migrate podcast-player onto NMP master (UniFFI facade + ADR-0069)

**Target:** NMP master tip (provisional; re-pin to the v-next release tag once
pablof7z/nostr-multi-platform#2690 cuts it).

**Priority:** P0 — blocks every other NMP-coupled change in this repo.

**Status:** In progress. A6/A7/A8 have moved the native app-facing surface to
explicit generated UniFFI methods across iOS, Android, TUI, and headless; the
old Rust C-ABI endpoint modules remain only as an internal implementation tail
behind the app-owned facade. Tactical tracking, scope, and acceptance criteria
for every slice live in GitHub Issues, not here — this file only orients readers
who land on `docs/plan.md` and need the target-state summary and pointers.
Canonical source: pablof7z/podcast-player#597 (epic) and its child issues
#680–#688.

## Why this rewrite exists

The original #597 (implemented, see `docs/plan/issue-605.md` and the pin bump
already on `main`) targeted `nmp_app_dispatch_action_bytes` as the C-ABI write
doorway in `nmp-ffi`. NMP's current `origin/master` has since **deleted
`nmp-ffi` entirely**, along with `nmp-signer-broker`, `nmp-defaults`, and the
JSON action doorway. This is not a route-through-a-new-symbol bump — it is a
full replacement of the C-ABI facade with a **UniFFI** facade:

- `nmp-ffi` deleted → `nmp-uniffi` (Swift/Kotlin bindings) + `nmp-native-runtime`
  (`NmpApp` handle, `NmpAppBuilder`, lifecycle, `dispatch_action_bytes_typed`)
  + `nmp-uniffi-support`.
- JSON `nmp_app_dispatch_action` doorway deleted → typed byte dispatch: encode
  a typed `ActionPayload` (FlatBuffers) into a `DispatchEnvelope`, call
  `dispatch_action_bytes_typed`.
- `nmp-defaults::register_defaults` dead (ADR-0069) → `nmp_substrate::install(...)`
  + explicit per-crate `register_*`.
- `nmp-signer-broker` deleted → NIP-46 rides the shared relay lane in
  `nmp-core` / `nmp_uniffi` identity::broker.

Reference facade shape: `apps/nmp-gallery/crates/nmp-app-gallery` in the NMP
repo (`lib.rs::install_gallery_composition`, `dispatch_bytes.rs`,
`configure_pre_start_for_app_facade`).

## Sequencing

Critical path: **A0 → A1 → A2 → {A3, A5} → A6 → {A7, A8}**, with A4 parallel
to A3 off A1. See #597 for the full table and per-slice blockers.

Epic B (Swift→Rust thin-shell ownership, #561/#601) is orthogonal and
deliberately sequenced *after* Epic A — see the note on #561.

## Known blockers picked up while landing A0/A1

- **`nmp-feedback` re-architecture** (pablof7z/nmp-feedback#3): the shared
  feedback-thread module depends on the deleted `nmp-ffi` JSON `nmp.publish`
  doorway with no generic replacement (writes are now typed, app-owned
  `ActionModule`s). A0 dropped the dependency (and the local vendored compat
  fork previously at `third-party/nmp-feedback`) rather than carry a shim
  forward. Feedback-thread integration returns as a follow-up slice once the
  upstream issue is resolved.
- **Provider-transport lane** (pablof7z/nostr-multi-platform#2726): the
  framework decision is closed; the app-owned UniFFI facade is the migration
  direction for A6/A8's ~20 LLM/STT/TTS BYOK RPCs.

## Validation

Each child issue records its own exact commands in its PR. At minimum across
the epic:

- `cargo metadata` resolves exactly one copy of each `nmp-*` crate (A0 gate).
- `cargo build -p nmp-app-podcast` green (A1 gate).
- `cargo test -p nmp-app-podcast`, focused TUI/headless action scenario
  tests, focused Android/iOS dispatch-wrapper builds, codegen/drift checks
  (later slices).
- `git diff --check`.
