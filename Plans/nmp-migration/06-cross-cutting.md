# Cross-cutting concerns

## 1. Persistence migration

The Codex review caught that my original "one JSON blob in
UserDefaults" model was wrong. The actual legacy stores are:

| Store | Path / scheme | Owned by |
|---|---|---|
| Metadata JSON | App Group `Application Support`, key `podcastr.state.v1` (see `App/Sources/State/Persistence.swift:260,289`) | `Persistence.swift` |
| Episode rows | App Group SQLite sidecar (see `EpisodeSQLiteStore.swift:60`) | `EpisodeSQLiteStore` |
| Transcripts | per-episode JSON files | `TranscriptStore.swift` |
| Wiki pages | per-page JSON files | `WikiStorage.swift` |
| Briefings | files + media (mp3) | `BriefingStorage.swift` |
| Chat history | files | `ChatHistoryStore.swift` |
| Cost ledger | file | `CostLedger.swift` |
| Episode audit log | file | `EpisodeAuditLogStore.swift` |
| Vector index | sqlite-vec (`VectorIndex.swift`) | `VectorIndex` |
| Now-playing snapshots | file (cross-process for widgets) | `NowPlayingSnapshotStore.swift` |
| Keychain (nsec, BYOK, NIP-46 sessions) | iOS Keychain | scattered |
| UserDefaults markers | "podcastr.review-prompt-last", etc. | scattered |

The migration is owned by `podcast-core::migration` (and per-store
sub-modules). It runs on first launch of the new app under a sentinel:

```rust
if !storage.has("podcastr.migration.v1.done") {
    migrate_metadata_json()?;
    migrate_episode_sqlite()?;
    migrate_transcripts()?;
    migrate_wiki_pages()?;
    migrate_briefings()?;
    migrate_chat_history()?;
    migrate_cost_ledger()?;
    migrate_audit_log()?;
    migrate_vector_index()?;   // expensive — see §1.2 below
    migrate_userdefaults_markers()?;
    storage.set("podcastr.migration.v1.done", true)?;
}
```

Native side: a `nmp.legacy_io.capability` (iOS-only) exposes file-read
+ App-Group-UserDefaults-read + SQLite-read primitives so Rust can pull
bytes from the legacy paths without violating D7. The capability has
no decisions; it returns raw bytes.

Per D6, migration failure surfaces as a toast and the sentinel stays
unset; next launch retries.

### 1.1 Keychain — no re-pairing if entitlements allow

The Sonnet review caught that
`App/Resources/Podcastr.entitlements` does NOT include
`keychain-access-groups`. The current app likely stores Keychain items
under its default per-app group (`$(AppIdentifierPrefix)$(CFBundleIdentifier)`).

Two scenarios:
- **Same bundle ID** (`io.f7z.podcast` preserved): Keychain items are
  readable by the new app without entitlement changes.
- **New bundle ID**: Keychain items not directly readable. Requires
  either (a) a transitional version of the old app that adds a shared
  `keychain-access-groups` entry, shipped to existing users before the
  new app replaces it; or (b) accept re-pairing and document the UX.

**Decision deferred to M1.** Audit the actual `kSecAttrAccessGroup`
used at write time. If the new app keeps `io.f7z.podcast`, no
re-pairing required and we can skip the transitional release.

### 1.2 Vector index migration

The sqlite-vec index can be large (potentially hundreds of MB across
years of transcripts). Migration options:

- **Re-index** (regenerate embeddings on first launch): user-visible
  cold start delay — minutes.
- **Adopt** (open the existing SQLite file in place under
  `nmp.vector.capability`): no delay, but requires the new schema to
  be backwards-compatible.

**Decision deferred to M6.** Default plan: adopt. If schema diverges,
re-index in background and surface progress via toast.

### 1.3 Audio download cache

Already-downloaded episode mp3 files live in
`Application Support/Downloads/`. The new `nmp.download.capability`
must accept these as pre-existing complete tasks (no re-download).
The migration step writes a `DownloadDomain` record per file based
on its episode id (parsed from filename or sidecar metadata).

## 2. NMP `docs/BACKLOG.md` entries this migration files

Each entry follows NMP planning discipline. File these in NMP repo as
a single PR before M0 starts. The orchestrator (merge gate) maintains
them.

1. **nmp-foundation-audit** — replace every reference to `DomainModule`,
   `ViewModule`, `IdentityModule` in plan with the shipped substrate.
   Codex's blocking finding.
2. **nmp-nip74-add** — new crate for podcast events (kind:30074, 30075).
   ADR pinning schema.
3. **nmp-blossom** — new crate for Blossom protocol.
4. **nmp-nip26-add** — delegation crate (verify if already inside
   `nmp-signer-iface` first).
5. **nmp-nip65-query** — explicit query module if `nmp-router` doesn't
   already export it.
6. **cap-audio** — `nmp.audio.capability` schema + ADR + Android stub.
7. **cap-download** — same.
8. **cap-notifications** — same.
9. **cap-stt** — same (no polling; webhook design required).
10. **cap-tts** — same.
11. **cap-vector** — raw primitives only (`KnnSearch`, `BM25Search`,
    not `QueryHybrid`).
12. **cap-spotlight** — iOS-only.
13. **cap-carplay** — iOS-only.
14. **cap-handoff** — iOS-only.
15. **cap-icloud** — iOS-only.
16. **cap-review** — iOS-only.
17. **cap-data-export** — multi-platform.
18. **cap-legacy-io** — iOS-only, used only during migration.
19. **cap-video** — clip export. May defer.
20. **apps-podcast-scaffolding** — accept `apps/podcast/` tree into
    NMP repo (mirror `apps/chirp/`).
21. **per-view-emit-rate** — extend `nmp-core` tick loop to support
    per-view emit rates so agent streaming tokens can hit 30 Hz.
    Required before M7. Sonnet review caught that the original plan
    assumed this exists.
22. **threading-podcast-peer** — confirm `nmp-threading` exposes the
    API `podcast-peer` needs; extend if not.

## 3. Test strategy

Five test surfaces, each enforced by CI:

| Surface | What it catches | When it runs |
|---|---|---|
| Rust unit | per-crate logic | every PR; scoped to touched crates per NMP rule |
| NMP integration (`nmp-testing`) | end-to-end Rust scenarios with mock relays + mock capabilities | every NMP PR |
| iOS smoke (XCUITest) | scenario tests; shared kernel; real-FFI; real-relay (selective) | every iOS PR |
| Snapshot conformance | golden `PodcastUpdate` JSON round-trips via Swift Decodable | every PR touching schema |
| UI copy fidelity (`ci/ui-copy-fidelity.sh`) | migrated `Features/` files match approved-diff patterns vs. legacy | every PR touching iOS |
| Doctrine lint (`cargo test -p nmp-testing --test doctrine_lint_smoke`) | D0/D7/file-size/no-polling regressions | every NMP push |
| Anti-business-logic lint (`ci/no-business-logic-in-swift.sh`) | forbidden patterns under iOS `Features/` | every iOS PR |

Pre-merge gate: full workspace `cargo test` + doctrine + iOS schemes
green.

## 4. Migration tooling

Under `ci/migration/` (Podcastr repo):
- `copy-features.sh` — `cp` walker + manifest.tsv.
- `apply-token-swap.swift` — SwiftSyntax AST edits.
- `split-features.swift` — SwiftSyntax class-excision.
- `verify-copy-fidelity.sh` — diff validator.
- `golden-screenshots/` — `swift-snapshot-testing` golden renders
  captured from the legacy app at migration start.

All of these are deterministic. Agents invoke them via `Bash`, never
Write a `Features/` file directly.

## 5. AGENTS.md disciplines

- File-size: 300 soft / 500 hard. Enforced by NMP and Podcastr CI.
- Typography: no serif fonts. Migration is mechanical — no new fonts
  introduced.
- Whats-new: every user-facing change adds an entry to
  `App/Resources/whats-new.json`. Migration milestones M1–M11 mostly
  invisible to users; sparse entries during. Big-bang entry at M12.
- Commits: no co-author, no Claude/Codex/agent attribution, no emojis,
  Conventional-Commits prefixes.
- Worktrees: every agent owns its own; reads `WIP.md` before starting;
  adds entry on start, removes on PR open.

## 6. Codex review

Every NMP-side PR runs codex post-merge review (existing NMP
convention). Findings saved to `docs/perf/codex-reviews/<sha>.md`.
Any actionable finding becomes a new NMP `docs/BACKLOG.md` entry.

Podcastr-side PRs reviewed by orchestrator: doctrine compliance,
file-size, anti-hallucination, test coverage.

## 7. Whats-new policy during migration

Most internal milestones invisible to users. Sparse entries:

- M1 (identity): "Identity moved to new architecture. No action needed."
  (only if user-observable change.)
- M2 (library): "Library now syncs faster (etag cache)." (likely.)
- M5 (transcripts): "On-device transcription on iOS 26." (if newly
  enabled.)
- M11 (platform): "CarPlay browse-tree improvements." (likely.)
- M12 (big bang): "Podcastr is now built on NMP. Same app, smarter
  brains. Android/web/desktop coming."

Per AGENTS.md "would the user notice?" — most M0–M10 entries skip.

## 8. Rolling back

If a milestone's exit gates fail and can't be made green in-flight,
the milestone is reverted (rebase to the merge base before the first
unit landed). Worktrees are discarded. The milestone is re-planned
based on the failure mode and re-attempted. There is no "ship behind
a feature flag" — features ship complete or not at all.

## 9. Effort estimate (revised)

Original: 8–12 person-months.

Codex revised: 18–30 person-months for true zero-hack scope.
Sonnet revised: 10–16 person-months if the foundational fixes are
done; more if hidden complexity (FeedbackStore, vector migration,
Live Activity, BYOK entitlement transition) costs as expected.

**Working estimate for this plan: 16–24 person-months** (one
person-month = one focused human-equivalent week per agent, ×
parallelism). Calendar time depends on agent fanout — with the
parallel work units in each milestone, realistic calendar time is
3–6 months at high parallel utilization.

Re-estimate at each milestone exit.
