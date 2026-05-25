# M4 — Background download capability

**Status:** unclaimed
**Scale:** M
**Depends on:** M2
**Blocks:** M5, M11
**Parallel work units:** 4

---

## Scope

`nmp.download.capability` lands. `EpisodeDownloadService` becomes pure
executor. Auto-download policy (newest-first cap, storage-aware,
network-type-aware) moves to Rust under `podcast-feeds::refresh::policy`.

---

## Pre-flight

- [ ] M2 exit green. M3 may be in progress in parallel.
- [ ] Confirm BACKLOG `cap-download` and ADR landed in NMP.
- [ ] Existing `Application Support/Downloads/` cache catalogued
      (filenames map to episode ids — verify the scheme used today).

---

## Parallel work units

### Unit M4.A — `nmp.download.capability` Rust + ADR

**Tasks:**
- [ ] Land `nmp-core::capability::download` (request/response/event
      enums per [`../03-capabilities.md`](../03-capabilities.md) §5.2).
- [ ] Resume-token handling: `Paused{resume_token?}` event; Rust
      persists in `DownloadDomain`.
- [ ] Android stub: WorkManager outline.
- [ ] ADR.

**Quality gates:**
- [ ] `cargo test -p nmp-testing` green.

### Unit M4.B — `podcast-feeds::refresh::policy`

**Tasks:**
- [ ] Auto-download decision: per subscription policy
      (NewestFirst{n}, AllNew, None), storage cap, current network
      type (cellular vs wifi), time of day window.
- [ ] Adopts pre-existing `Application Support/Downloads/` files on
      first launch — emits `Completed` events for them.
- [ ] Cleanup policy: prune oldest played + completed episodes when
      cap reached.

**Quality gates:**
- [ ] Unit tests for each policy variant with mock clock + mock
      storage.

### Unit M4.C — iOS DownloadCapability executor

**Tasks:**
- [ ] Create `Capabilities/DownloadCapability.swift`.
- [ ] Background `URLSession` with the legacy identifier (preserves
      in-flight downloads from the legacy app on first launch).
- [ ] Delegate methods (`urlSession(_:downloadTask:didFinishDownloadingTo:)`,
      `didWriteData`, etc.) emit progress/completion events.
- [ ] On app launch, re-register session and replay accrued events.
- [ ] No retry policy in Swift — failures emit `Failed{reason}` only.

**Quality gates:**
- [ ] Manual: kill app mid-download; relaunch; download resumes.
- [ ] Lint: no business logic.

### Unit M4.D — UI: download progress in EpisodeRow + Settings → Downloads

**Tasks:**
- [ ] EpisodeRow already migrated in M3 — verify progress bar reads
      `model.snapshot?.downloads[episodeId]`.
- [ ] `Features/Settings/DownloadsManagerModels.swift` was flagged by
      Sonnet — split (excise the manager model class; the View part
      stays). Status labels, progress, action choices come from Rust
      projection.

**Quality gates:**
- [ ] Goldens match for Downloads sheet.

---

## Sequential integration

- [ ] Merge M4.A, M4.B, M4.C, M4.D in order.
- [ ] Live test: subscribe to 5 podcasts on cellular vs. wifi;
      verify policy fires appropriately.

---

## Exit checklist

- [ ] Auto-download fires per policy.
- [ ] Existing legacy downloads adopted (no re-download).
- [ ] Pause / resume / cancel work.
- [ ] Storage cap honored.
- [ ] **Swift files deleted:**
  - `App/Sources/Services/EpisodeDownloadService.swift`
  - `App/Sources/Services/EpisodeDownloadService+AutoDownload.swift`
  - `App/Sources/Services/EpisodeDownloadService+Delegate.swift`
  - `App/Sources/Features/Settings/DownloadsManagerModels.swift` (class part)
- [ ] M5 unblocked.

## Hand-off to M5

M5 can rely on: episode audio files available at known paths; download
progress visible in snapshot.
