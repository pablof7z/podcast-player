# NMP v0.2.2 Upgrade Changelog

**Old revision/tag:** `7be4a771b59228f4b51e2ba7cfce481734d4da9a` (`nmp-v0.2.1`)
**New revision/tag:** `6a0c4fdab48d324a1be24ce361e030c1143a4295` (`nmp-v0.2.2`)
**Nature of change:** Dependency revision bump. **C-ABI is non-breaking — no symbol migration required by the podcast app.** One C-ABI symbol was renamed upstream (`timeline_insert_events` → `timeline_insert_event_batch`), but the podcast app never used that symbol; no podcast-app code changes were required.

---

## TLDR

Pin bump of the four git-pinned NMP workspace dependencies (`nmp-app-template`,
`nmp-core`, `nmp-ffi`, `nmp-signer-broker`) from rev `7be4a771` to rev `6a0c4fda`
(tag `nmp-v0.2.2`). The workspace package version string remains `0.2.1` in the
NMP crates at this tag.

The headline upstream changes are: (1) a replaceable-event freshness/TTL tracking
subsystem (`F-ttl`) in `nmp-core` and `nmp-nostr-lmdb`, and (2) an iOS Home Feed
view wiring in the Chirp shell. The podcast app is unaffected by both. The one
C-ABI rename (`timeline_insert_events` → `timeline_insert_event_batch`) is also
a no-op for the podcast app (zero usages).

### Verification

| Layer | Command | Result |
|---|---|---|
| 1 — workspace compile | `cargo check --workspace` | Pass (~28s). All NMP crates resolve at rev `6a0c4fda`. `Cargo.lock` updated; zero remaining references to the old rev `7be4a771`. Two pre-existing local dead-code warnings (`CompileOutcome` in `ai_chapters.rs`, unread `nostr_results` field) unrelated to NMP. |
| 2 — iOS-sim build | `cargo build -p nmp-app-podcast --target aarch64-apple-ios-sim` | Pass (~17s). No linker errors; same two pre-existing warnings only. |
| 3 — iOS device Xcode build | `build_device` via MCP | Pass. |

---

## What changed upstream in v0.2.2

### Added

1. **Replaceable event freshness / TTL tracking** (`F-ttl`): a new subsystem in
   `nmp-core` and `nmp-nostr-lmdb` that assigns `freshness: "fresh"` to newly
   ingested replaceable events, computes TTL from `kind → freshness → epoch`, and
   tracks three freshness levels (`fresh` / `stale` / `expired`). Events enter
   the LMDB store through `timeline_insert_events` (single) and
   `timeline_insert_event_batch` (batch) — `ReplaceableTtlActor` manages the
   transition lifecycle asynchronously. **Podcast app: no adoption required.**

2. **iOS Home Feed view wiring** (Chirp-iOS shell only): `HomeFeedView` is bridged
   into the Chirp `RootShell` with a native SwiftUI timeline. This is internal to
   the Chirp shell and does not affect the podcast app's Swift bridge or generated
   types.

### Changed

3. **`timeline_insert_events` → `timeline_insert_event_batch`** (C-ABI rename):
   the singular FFI entry point is renamed. All first-party shells (iOS
   `KernelBridge.swift`, chirp-tui, chirp-desktop) have been updated upstream.
   **The podcast app never referenced this symbol** (zero hits in Rust, Swift, or
   generated headers) — no migration required.

### Fixed

4. **`nmp-nostr-lmdb` `Error::Io` wraps `io::Error` not `String`**: a type
   correction fix for a master-branch breakage. Transparent to the podcast app.

---

## What the podcast app adopted

**Nothing.** This is a pure pin bump with no required podcast-app code changes.

---

## What's optional next (not in this PR)

The items deferred from previous upgrades remain open:

- **`resolved_profiles` projection decode** — removes a proven-broken merge
  pattern; should be adopted soon (flagged since v0.2.0).
- **`bunker_connection_state` projection decode** — available in snapshot but
  not decoded.
- **`configured_relays` projection decode** — available but not decoded; pairs
  naturally with a relay-edit UI.
- **`NmpApp::active_account_handle()` as canonical pubkey source** — not yet
  adopted.
