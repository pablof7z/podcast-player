# M2 — Podcast domain (feeds)

**Status:** unclaimed
**Scale:** L (3–6 weeks wall)
**Depends on:** M1
**Blocks:** M3–M13
**Parallel work units:** 6

---

## Scope

Bring up the podcast domain (Podcast, Episode, Subscription, Chapter,
Person, SoundBite, AutoDownload, Triage, Category, AdSegment). Port
the RSS parser, OPML I/O, Podcasting 2.0 chapters, subscription
refresh, etag cache. Library, DiscoverSearchForm, OPMLImportSheet UI
all render unchanged.

Also: **first second-platform proof** (Codex review finding — Android
or web stub must exercise dispatch + snapshot decode + one capability
at this milestone).

---

## Pre-flight

- [ ] M1 exit checklist green.
- [ ] **API audit:** read existing NMP storage interfaces
      (`nmp-store`, `nmp-nostr-lmdb`). Confirm SQLite + LMDB are
      usable from `apps/podcast/podcast-core`.
- [ ] Sample RSS feeds saved to
      `apps/podcast/podcast-feeds/tests/fixtures/`:
      Tim Ferriss, NPR Up First, Lex Fridman, Daring Fireball, plus
      one Podcasting-2.0 feed with chapters + persons + soundbites.
- [ ] Sample OPML files for round-trip.

---

## Parallel work units

### Unit M2.A — `podcast-core` types + projections

**Owner:** _(unclaimed)_
**Worktree:** `nostrmultiplatform-worktree-m2a/`

**Tasks:**
- [ ] Create crate per [`../02-crates.md`](../02-crates.md) §C.
- [ ] Port domain types from
      `App/Sources/{Domain,Podcast}/*.swift` per
      [`../05-migration-map.md`](../05-migration-map.md) §B + §D.
- [ ] Projections: `LibraryProjection`, `EpisodeProjection`,
      `TriageProjection`, `CategoryProjection`, `ClipProjection`,
      `LibraryDisplayProjection` (Rust precomputes accent colors,
      symbols, % progress — Sonnet review finding).

**Quality gates:**
- [ ] `cargo test -p podcast-core` — 80%+ branch coverage of typed
      logic.
- [ ] No file > 300 LOC.
- [ ] Doctrine lint green.

### Unit M2.B — `podcast-feeds` RSS streaming parser

**Owner:** _(unclaimed)_
**Worktree:** `nostrmultiplatform-worktree-m2b/`

**Tasks:**
- [ ] Port `RSSItemAccumulator.swift`, `RSSParser.swift`,
      `RSSParserDelegate.swift`, `RSSDateParsing.swift` to Rust
      streaming SAX (use `quick-xml`).
- [ ] Port `ChaptersClient.swift` (Podcasting 2.0).
- [ ] Port `FeedClient.swift` orchestration (HTTP via
      `nmp.http.capability`).

**Quality gates:**
- [ ] Sample feeds round-trip to identical episode lists vs. legacy
      Swift parser output (capture legacy output as test fixture).

### Unit M2.C — `podcast-feeds` OPML + refresh policy

**Owner:** _(unclaimed)_

**Tasks:**
- [ ] Port `OPMLImport.swift`, `OPMLExport.swift`.
- [ ] Port `SubscriptionRefreshService.swift` policy: which feed to
      refresh when, etag/lastModified cache, parallel refresh
      strategy.
- [ ] Wire to actions `RefreshFeed`, `RefreshAllFeeds`, `ImportOpml`,
      `ExportOpml`.

**Quality gates:**
- [ ] OPML round-trip identical.
- [ ] Refresh schedule unit-tested with mock clock.

### Unit M2.D — Persistence migration

**Owner:** _(unclaimed)_

**Tasks:**
- [ ] Create `nmp.legacy_io.capability` (iOS-only) per
      [`../03-capabilities.md`](../03-capabilities.md) (file BACKLOG
      if not from M0).
- [ ] `podcast-core::migration::from_legacy_app` reads:
      - Metadata JSON at App-Group `podcastr.state.v1`.
      - SQLite episode sidecar.
      - Audit log file.
      Migrates into `nmp-store` LMDB.
- [ ] Sentinel `podcastr.migration.v1.done` written on success.
- [ ] Surfaces failure as toast (D6); never throws.

**Quality gates:**
- [ ] On a device snapshot with legacy data, migration runs to
      completion in ≤30s and the snapshot reflects all subscriptions.
- [ ] Idempotent — second launch is a no-op.

### Unit M2.E — UI migration: Library + DiscoverSearchForm + OPMLImportSheet

**Owner:** _(unclaimed)_
**Worktree:** `podcast-worktree-m2e/`

Files:
- `App/Sources/Features/Library/*.swift` (all)
- The split file: `Features/Library/LibraryDerivedDisplay.swift` (133
  LOC) — class `LibraryDerivedDisplay` excised; the computed display
  fields come from `library_display` projection now.

**Tasks:**
- [ ] `cp` via tooling. Run `split-features.swift` for
      `LibraryDerivedDisplay.swift` (excise the class). Apply
      token-swap.
- [ ] Capture/match goldens for: empty library, library with N=5/N=50
      shows, search-active, OPML-import sheet states.
- [ ] DiscoverSearchForm: search dispatch routes through
      `podcast-discovery::itunes` action.

**Quality gates:**
- [ ] Snapshot tests match legacy goldens.
- [ ] No `LibraryDerivedDisplay` class in copied files.
- [ ] Search debounces in Rust, not Swift.

### Unit M2.F — Second-platform proof (Android or web)

**Owner:** _(unclaimed)_
**Worktree:** as appropriate

**Tasks:**
- [ ] Stand up a minimal `android/Podcast/` Compose project OR
      `web/podcast/` React project (pick one; default Android).
- [ ] Link `nmp-app-podcast` as cdylib (Android via cargo-ndk; web via
      wasm-bindgen).
- [ ] Implement a stub for the audio capability ("Unsupported"
      response is fine for M2) + Keychain + HTTP capability.
- [ ] One screen: a list of subscribed podcasts read from the
      snapshot. Compose `ListItem` per `PodcastSummary`.
- [ ] Wire NIP-46 onboarding via the existing nmp-signer-broker; one
      sign-in works.

**Quality gates:**
- [ ] Android/web build green.
- [ ] App boots; reads subscriptions; renders the list with the same
      titles iOS shows.
- [ ] Same `cargo` binary used by iOS — no logic forked.

---

## Sequential integration

- [ ] Merge M2.A.
- [ ] Merge M2.B + M2.C (feeds work depends on M2.A types).
- [ ] Merge M2.D (persistence migration; requires types).
- [ ] Merge M2.E (UI; requires snapshot fields from A/B/C).
- [ ] Merge M2.F (second-platform proof; can land in parallel after
      M2.A).
- [ ] Live test: subscribe to 5 real podcasts; verify episodes
      populate; OPML export + reimport identical.

---

## Exit checklist

- [ ] All units merged.
- [ ] Library tab renders identical to legacy (pixel-equivalent per
      goldens).
- [ ] Discover Popular Now + search works.
- [ ] OPML import + export work.
- [ ] etag cache halves refresh bandwidth on second run.
- [ ] First second-platform proof boots and shows subscribed list.
- [ ] **Swift files deleted at end:**
  - `App/Sources/Podcast/*.swift` (all 20)
  - `App/Sources/Domain/{Anchor,Clip,EpisodeComment,Friend,ItemColorTag,Note,NoteAuthor,RelativeDateBucket,RelativeTimestamp,Settings,ThreadingMention,ThreadingTopic}.swift`
  - `App/Sources/State/*.swift` (all 27 — AppStateStore + extensions + Persistence + sidecar)
  - `App/Sources/Services/{SubscriptionRefreshService,SubscriptionService,ITunesSearchClient}.swift`
  - `App/Sources/Services/EpisodeMetadataIndexer.swift`
  - `App/Sources/Services/EpisodeAuditLogStore.swift`
  - `App/Sources/Services/NowPlayingSnapshotStore.swift` (replaced by snapshot field; widget code reads new file)
  - The Library/LibraryDerivedDisplay class (file kept; class excised)
- [ ] Whats-new entry: "Library now syncs faster" (optional).
- [ ] M3 unblocked.

## Hand-off to M3

M3 can rely on:
- Subscriptions + episodes available in snapshot.
- Episode metadata (URL, duration, position) accessible.
- The `now_playing` snapshot field is wired (empty until M3 fills it).
- Auto-download policy in Rust (decisions made; no execution yet
  because that's M4).
