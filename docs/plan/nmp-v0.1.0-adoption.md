# NMP v0.1.0 Adoption Plan

Adoption of the new NMP v0.1.0 capabilities in the podcast-player iOS app. The
dependency pin is already bumped and verified (committed on `main` as
`1449d31f`); this plan covers ADOPTION only, not the upgrade. Raw input is the
"Follow-up Backlog Items" section of `docs/plan/nmp-v0.1.0-upgrade.md`.

## ⚠️ CORRECTION (2026-05-28, verified) — supersedes the recommendation below

Live testing + source review overturned the original "Swift-only, defer the rest"
recommendation. The real root cause: the podcast app gets its projection via a
**bespoke pull symbol** (`nmp_app_podcast_snapshot`/`_rev`/`_free`, defined in
`apps/nmp-app-podcast`) that the iOS shell **polls every 500ms**
(`KernelModel.startSnapshotPoll`). That is a D8 polling violation and the reborn
deprecated `nmp_app_chirp_snapshot` anti-pattern.

Verified: on a bare launch the reactive push callback fires but every frame is a
1-byte payload that fails to decode — because **no `podcast.*` projection is
registered through the canonical seam** `nmp_app_register_snapshot_projection`
(`nmp-ffi/src/snapshot.rs:83`), so `KernelSnapshot::projections` has nothing to
emit. `store_open_failure` rides that same empty push frame, which is why it never
surfaces (and why **PR #135 does not work for the startup case and must not merge
as the final fix**).

**Correct fix (subsumes `store_open_failure`):** register the podcast projection
through `nmp_app_register_snapshot_projection(app, "podcast.<key>", projector)` so
it rides the reactive push frame; read podcast data (and `store_open_failure`) from
the pushed `update.projections["podcast.<key>"]` in the existing `apply()` path;
**delete** the three bespoke pull symbols and `startSnapshotPoll()`. NOT the
ADR-0037 typed sidecar (that's an NMP-internal per-key optimization, not the
app-onto-push mechanism). Blast radius: Swift bridge + `apps/nmp-app-podcast`
(register projector) + `android.rs` + headless harness — all four consume the
bespoke pull symbols today. See memory `project_podcast_projection_must_use_push_seam`.

---

## Scope recommendation (read first) — SUPERSEDED, see correction above

| Item | Verdict | Size |
|---|---|---|
| 1. `store_open_failure` user-facing surface (MANDATORY) | **NOW** | Small, Swift-only |
| 4. TUI unused-import warning | **NOW** (ride-along) | Trivial, one line |
| 2. `active_account_handle()` adoption | **DEFER** | Pure churn today |
| 3. ADR-0037 typed FlatBuffers sidecar | **DEFER** | Blocked, speculative |

**Fan-out recommendation: NO fleet. Do this as a single sequential change (one
worktree, one PR), with the TUI one-liner folded into the same PR.** The only
mandatory item is small and Swift-only (≈4 files + 1 test + 1 whats-new line),
and the only other NOW item is a one-line `cargo fix`. A multi-agent fan-out
would cost more coordination overhead than the work itself. One agent, one
branch, one PR.

### Why DEFER items 2 and 3

- **Item 2 (`active_account_handle`)** — The active pubkey already reaches the
  Swift shell reactively on every snapshot tick: `KernelIdentityProjection.decode`
  reads `projections.active_account` from the generic update-callback envelope
  (`App/Sources/Bridge/KernelIdentityProjection.swift:128-153`), and
  `PodcastUpdate.activeAccount` carries it on the pull path. `active_account_handle()`
  is a Rust-only accessor with **no C-ABI export today** — adopting it would
  require a new `nmp_app_active_account` FFI symbol in `nmp-ffi` (upstream) plus
  a Swift wrapper, all to replace a value that already arrives reactively. It is
  also a synchronous slot read, which runs against the project's "Nostr code must
  be reactive — no polling" rule (`memory/feedback_nostr_reactive.md`). Net: pure
  churn with a security-sensitive blast radius (identity/signer path). Revisit
  only if a concrete synchronous-between-ticks pubkey need appears (none today).
- **Item 3 (ADR-0037 typed sidecar)** — Depends on a podcast home-feed migration
  to an `OpFeedEngine`-style projection that does not exist yet. The wire is
  backward-compatible and inert until adopted. Defer until/unless the feed
  migration lands.

---

## Item 1 — `store_open_failure` (MANDATORY) — end-to-end spec

### Verified finding: SWIFT-ONLY. No Rust change required.

Evidence trail:

- `store_open_failure: Option<String>` is a **top-level field on the generic
  `KernelUpdate` snapshot**, a sibling of `projections` / `last_error_toast`
  (`nostr-multi-platform/crates/nmp-core/src/kernel/update.rs:173`, struct field
  at `kernel/types.rs:822`). It is `skip_serializing_if = None`, so absent in
  healthy sessions.
- The podcast app DOES configure the kernel LMDB store —
  `App/Sources/Bridge/KernelBridge.swift:39` calls `nmp_app_set_storage_path`
  with `<App Support>/NMP/`. So the failure CAN fire; surfacing it is real, not
  theoretical.
- The generic update callback (`nmp_app_set_update_callback`) delivers the
  generic `KernelUpdate` JSON to Swift as `{"t":"snapshot","v":<KernelUpdate>}`.
  Proof that `v` is the generic snapshot (not the podcast pull snapshot):
  `KernelIdentityProjection.decode(envelopePayload:)` reads
  `outer["v"]["projections"]["active_account"]` off that exact callback payload
  in production (`KernelIdentityProjection.swift:128-153`). `projections` only
  exists on the generic `KernelUpdate`. Therefore `store_open_failure` is
  **already in the bytes Swift receives** — `PodcastUpdate`'s `Codable` simply
  drops the unknown key.
- `grep store_open_failure` across the whole podcast repo returns **zero** hits —
  no podcast code reads it yet.

Conclusion: a raw second-pass read of `outer["v"]["store_open_failure"]`,
mirroring the existing identity decode, is the complete plumbing. **No
`PodcastUpdate` (Rust) change, no generated-Swift-mirror change, no new FFI
symbol.**

### Important routing constraint

`store_open_failure` rides the **PUSH/callback path** (`kernel.listen` →
`KernelBridge.decode` → `apply(result:)`). It does **NOT** ride the PULL path
(`nmp_app_podcast_snapshot` / `PodcastUpdate`), and `build_podcast_update` never
sets it. Therefore it cannot be routed through the existing
`AppStateStore+KernelProjection` projection (that projection is fed by the pull
`podcastSnapshot`, which lacks the field). It must be surfaced as a new field on
`KernelModel`, read in the UI via the existing `.environment(kernelModel)`.

Do **NOT** reuse `lastErrorToast` — it is set in `KernelModel` but rendered in no
view (dead scaffold). Reusing it would make the mandatory alert invisible and
violate the no-scaffold rule. Wire a real `.alert`.

### Shipping target confirmation

`Project.swift:69` sets the iPhone app target `sources: ["App/Sources/**"]` and
bridging header `App/Sources/Bridge/NmpCore.h` (line 93). The parallel
`ios/Podcast/Podcast/**` tree is **not referenced by any Tuist target** — it is a
stale legacy mirror (consistent with `docs/plan.md`: "App/Sources/ remains the
reference implementation"). **All edits target `App/Sources/`. Do not touch
`ios/Podcast/`.**

### File-level task list

1. **`App/Sources/Bridge/KernelBridge.swift`**
   - In `decode(pointer:)`, after the existing
     `KernelIdentityProjection.decode(envelopePayload: data)` call, extract the
     top-level failure string with one `JSONSerialization` read:
     `(try? JSONSerialization.jsonObject(with: data) as? [String:Any])?["v"] as?
     [String:Any])?["store_open_failure"] as? String`. (One extra parse, or
     reuse the object the identity decoder already parses if refactoring to a
     single parse is cheap — keep it simple, a second parse is acceptable and
     matches the existing two-decoder convention.)
   - Add `let storeOpenFailure: String?` to `struct KernelUpdateResult` and pass
     it through the `KernelUpdateResult(...)` initializer.

2. **`App/Sources/Bridge/KernelModel.swift`**
   - Add `private(set) var storeOpenFailure: String?` (sibling of
     `lastErrorToast` at line 53).
   - In `apply(result:)` (line 346), assign
     `storeOpenFailure = result.storeOpenFailure`. Assign on every accepted tick
     so a recovered session (field returns to `nil`) clears the condition.
   - In `resetAndRestart()` (line 162) reset `storeOpenFailure = nil` alongside
     the existing `lastErrorToast = nil`.

3. **`App/Sources/App/RootView.swift`**
   - Add `@Environment(KernelModel.self) var kernelModel` (the model is already
     injected via `.environment(kernelModel)` in `AppMain.swift:43`).
   - Add a dismissable `@State private var storeFailureAlertDismissed = false`.
   - Attach a `.alert(...)` modifier to the root `tabBar` chain (same pattern as
     the existing `.alert(...isPresented:)` usages, e.g.
     `Features/Home/HomeView.swift:94`). Bind `isPresented` to a computed binding
     that is `true` when `kernelModel.storeOpenFailure != nil &&
     !storeFailureAlertDismissed`; the "OK" action sets
     `storeFailureAlertDismissed = true`. Title: "Storage Unavailable". Message:
     a user-readable line that includes the degraded-mode consequence (data this
     session will not persist), optionally appending the reason string. Reset
     `storeFailureAlertDismissed = false` via `.onChange(of:
     kernelModel.storeOpenFailure)` so a *new* failure re-presents but repeated
     identical ticks do not.
   - Keep RootView under the 500-line hard limit (currently 417). If the alert +
     binding pushes it close, extract the alert into a small
     `View` extension/modifier file (e.g.
     `App/Sources/App/RootView+StoreFailureAlert.swift`).

4. **`App/Resources/whats-new.json`**
   - Prepend one entry with a fresh unique UTC `shipped_at` and a single
     user-facing line, e.g.: "If on-device storage can't be opened the app now
     warns you instead of silently losing this session's data." Verify the
     timestamp is unique and newer than the current newest entry.

### Validation (Item 1)

- **Primary (deterministic, proves the wire):** add a Swift decode test under
  `AppTests/Sources/` (e.g. `StoreOpenFailureDecodeTests.swift`) that feeds a
  synthetic envelope
  `{"t":"snapshot","v":{"running":true,"rev":1,"schema_version":1,"store_open_failure":"lmdb open failed: ..."}}`
  to `PodcastHandle.decode` (or the extracted parse helper) and asserts
  `KernelUpdateResult.storeOpenFailure == "lmdb open failed: ..."`. Add a second
  case with the key absent and assert `nil`. (Mirror the existing
  `ChaptersClientDecodeTests` / `SettingsCodableRoundTripTests` style.)
- **Build gate:** `tuist generate` then an iOS-sim build of the app target
  (xcodebuild). Run the focused test bundle:
  `xcodebuild test ... -only-testing:PodcastrTests/StoreOpenFailureDecodeTests`.
- **Manual live-sim proof (secondary):** force the kernel LMDB open to fail by
  making `<App Support>/NMP` unopenable — e.g. pre-create a *regular file* named
  `NMP` where `KernelBridge.configureStoragePath` expects a directory (or revoke
  write perms on the parent). Launch the app and confirm the "Storage
  Unavailable" alert appears once and dismisses cleanly. Restore the directory
  and confirm a clean launch shows no alert.
- `git diff --check` before PR.

---

## Item 4 — TUI unused-import warning (ride-along)

### Verified finding

`apps/podcast-tui/src/app.rs:4` is `use crate::bridge::NmpEvent;` and `NmpEvent`
appears exactly once in the file (the import line) — confirmed unused.

### Task

- Remove the unused `use crate::bridge::NmpEvent;` line from
  `apps/podcast-tui/src/app.rs` (or run `cargo fix -p podcast-tui`).

### Validation (Item 4)

- `cargo check -p podcast-tui` is clean with no unused-import warning.
- Internal-only change. **No `whats-new.json` entry** (not user-facing).

---

## Sequencing & parallelism

- Items 1 and 4 are independent and both small; do them in the **same worktree
  and the same PR**. No ordering constraint between them.
- Within Item 1, the file order is: KernelBridge → KernelModel → RootView →
  whats-new → test. Each step depends on the previous type/field existing.
- Items 2 and 3 are deferred and not part of this PR.

## Risks

- **Identity / nsec (Item 2 only, deferred):** anything touching
  `active_account_handle` sits on the signer path. The nsec is forwarded straight
  to the kernel FFI (`KernelBridge+Identity.swift:34-36`,
  `nmp-ffi/src/identity.rs::nmp_app_signin_nsec`) and MUST NOT be logged.
  Deferring Item 2 keeps this PR away from that surface entirely. Item 1 reads
  only a non-secret diagnostic string and does not go near identity.
- **Worktree vs in-place-on-main tension:** the pin was committed in place on
  `main` (`1449d31f`) by the upgrade agent, but per `AGENTS.md` all *adoption*
  implementation work must happen in a per-agent worktree off `main` with a PR.
  This plan's work is adoption, so it follows the worktree+PR rule — do not
  continue editing in place on `main`.
- **Dead-scaffold trap:** `lastErrorToast` looks reusable but renders nowhere.
  The plan deliberately does not reuse it; a real `.alert` is required so the
  MANDATORY surface is actually visible.
- **Re-present storm:** `store_open_failure` is emitted on *every* tick while
  LMDB is down. The dismissable `@State` + `.onChange` gating (Item 1, step 3)
  prevents the alert from re-presenting on every frame.
- **File-limit risk:** RootView is at 417/500 lines; extract the alert to a
  modifier file if the addition risks crossing 500.
