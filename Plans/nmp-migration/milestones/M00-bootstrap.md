# M0 — Bootstrap

**Status:** unclaimed
**Scale:** S (≤1 week wall)
**Depends on:** none (after the foundation BACKLOG entries land — see Pre-flight)
**Blocks:** every other milestone
**Parallel work units:** 4

---

## Scope

Stand up the skeletons:
- `apps/podcast/nmp-app-podcast` Rust crate (mirror `apps/chirp/nmp-app-chirp`).
- `ios/Podcast/` Xcode project (mirror `ios/Chirp/`).
- Migration tooling (`ci/migration/*`) so subsequent milestones can `cp`
  legacy files in.
- Lint gates (`ci/no-business-logic-in-swift.sh`,
  `ci/ui-copy-fidelity.sh`).
- One copied UI file (`OnboardingView.swift`) wired to a placeholder
  `KernelModel` field — proves the bridge end-to-end.

No business logic ports yet. No real data flow yet. M0 proves the
skeleton boots and that the lint gates work.

---

## Pre-flight

Open these in the indicated repos. All boxes must be checked before
any unit is claimed.

- [ ] NMP `docs/BACKLOG.md` contains the 22 entries listed in
      [`../06-cross-cutting.md`](../06-cross-cutting.md) §2. File them
      as a single NMP PR if missing.
- [ ] **R1 foundation audit.** Read
      `/home/pablo/Work/nostrmultiplatform/crates/nmp-core/src/substrate/mod.rs`.
      Confirm shipped traits (`ActionModule`, `CapabilityModule`,
      `DomainMigration`, `KernelEventObserver`). Update
      [`../02-crates.md`](../02-crates.md) §A if anything's stale.
- [ ] Read [`../00-rules.md`](../00-rules.md) and
      [`../01-architecture.md`](../01-architecture.md). They bind every
      unit.
- [ ] `Plans/WIP.md` exists in the Podcastr repo (create if absent).
- [ ] Chirp's iOS schemes build green in your local checkout. If they
      don't, the migration can't use Chirp as reference.

---

## Parallel work units

### Unit M0.A — Rust crate skeleton

**Owner:** _(unclaimed)_
**Worktree:** `/home/pablo/Work/nostrmultiplatform-worktree-m0a/`
**Files created:**
- `apps/podcast/nmp-app-podcast/Cargo.toml`
- `apps/podcast/nmp-app-podcast/src/lib.rs`
- `apps/podcast/nmp-app-podcast/src/ffi/{mod,register,handle,snapshot,actions}.rs`

**Tasks:**
- [ ] `cp -r apps/chirp/nmp-app-chirp/{Cargo.toml,src}` to the new
      path; rename `nmp-app-chirp` → `nmp-app-podcast`; rename
      `ChirpHandle` → `PodcastHandle`, etc.
- [ ] Strip Chirp-specific deps (`nmp-marmot`, Chirp views). Keep:
      `nmp-core`, `nmp-ffi`, `nmp-signer-broker`, `nmp-app-template`.
- [ ] `src/ffi/register.rs` invokes only
      `nmp_app_template::register_defaults` for now — no podcast modules
      yet. Returns a `PodcastHandle` whose snapshot is "hello".
- [ ] `src/ffi/snapshot.rs` returns a stub JSON
      `{"running":true,"rev":0,"schema_version":1}`.
- [ ] Add to workspace `Cargo.toml` at NMP root.

**Quality gates:**
- [ ] `cargo build -p nmp-app-podcast --target aarch64-apple-ios` green.
- [ ] `cargo build -p nmp-app-podcast --target aarch64-apple-ios-sim` green.
- [ ] `cargo test -p nmp-testing --test doctrine_lint_smoke` green.
- [ ] No file in this crate exceeds 300 LOC soft (500 hard).

---

### Unit M0.B — iOS project skeleton + Bridge files

**Owner:** _(unclaimed)_
**Worktree:** `/home/pablo/Work/podcast-worktree-m0b/`
**Files created:**
- `ios/Podcast/project.yml` (xcodegen)
- `ios/Podcast/Podcast/App/{PodcastApp,RootShell}.swift`
- `ios/Podcast/Podcast/Bridge/NmpCore.h`
- `ios/Podcast/Podcast/Bridge/KernelBridge.swift`
- `ios/Podcast/Podcast/Bridge/KernelBridge+Decode.swift`
- `ios/Podcast/Podcast/Bridge/KernelBridge+Callbacks.swift`
- `ios/Podcast/Podcast/Bridge/KernelBridge+Types.swift`
- `ios/Podcast/Podcast/Bridge/KernelBridge+Actions.swift`
- `ios/Podcast/Podcast/Bridge/KernelModel.swift`
- `ios/Podcast/Podcast/Bridge/Generated/PodcastTypes.generated.swift`
- `ios/Podcast/Podcast/Theme/PodcastTheme.swift`

**Tasks:**
- [ ] Copy Chirp's `project.yml`; adapt bundle ID `io.f7z.podcast`,
      target name `Podcast`, lib name `-lnmp_app_podcast`, search
      paths under `target/aarch64-apple-ios{,-sim}/{debug,release}`.
- [ ] Copy Chirp's `KernelBridge.swift` (1895 LOC) split into ≤300 LOC
      files per the structure above. Use `Edit` with exact strings to
      partition by section — never retype.
- [ ] `KernelModel.swift` mirrors Chirp's; replace `ChirpHandle` →
      `PodcastHandle`, swap snapshot type to (placeholder)
      `PodcastUpdate`.
- [ ] `PodcastTheme.swift` mirrors Chirp's `ChirpTheme.swift`; tokens
      ported from Podcastr's `App/Sources/Design/AppTheme.swift`
      verbatim.
- [ ] xcodegen + xcodebuild green; app launches in iOS Simulator to a
      blank tab shell.

**Quality gates:**
- [ ] `xcodegen generate` succeeds.
- [ ] `xcodebuild -scheme Podcast -destination 'platform=iOS Simulator,name=iPhone 16'` succeeds.
- [ ] App launches; kernel actor logs "alive" once.
- [ ] No file > 300 LOC.

---

### Unit M0.C — Capabilities scaffolding

**Owner:** _(unclaimed)_
**Worktree:** `/home/pablo/Work/podcast-worktree-m0c/`
**Files created:**
- `ios/Podcast/Podcast/Capabilities/PodcastCapabilities.swift` (dispatcher)
- `ios/Podcast/Podcast/Capabilities/KeychainCapability.swift` (verbatim from Chirp)
- `ios/Podcast/Podcast/Capabilities/HttpCapability.swift` (verbatim from Chirp + widening stubs)

**Tasks:**
- [ ] `cp` from `ios/Chirp/Chirp/Capabilities/{ChirpCapabilities,KeychainCapability,HttpCapability}.swift`.
- [ ] Rename `ChirpCapabilities` → `PodcastCapabilities`.
- [ ] In `HttpCapability.swift`, add empty TODO methods for the M5/M8
      streaming features (SSE, WS). Leave bodies empty + a fatalError
      stub guarded by `#if DEBUG` — to be filled in later milestones.
      Each TODO logs the milestone that fills it.
- [ ] Wire dispatcher into `KernelBridge` via the capability callback
      Chirp uses.

**Quality gates:**
- [ ] App boots and capability callback is registered (verified by a
      `print` in dispatcher's no-op path).
- [ ] No file > 300 LOC.

---

### Unit M0.D — Migration tooling + lint gates

**Owner:** _(unclaimed)_
**Worktree:** `/home/pablo/Work/podcast-worktree-m0d/`
**Files created:**
- `ci/migration/copy-features.sh`
- `ci/migration/apply-token-swap.swift` (SwiftSyntax CLI)
- `ci/migration/split-features.swift` (SwiftSyntax CLI)
- `ci/migration/verify-copy-fidelity.sh`
- `ci/migration/manifest.tsv` (initially empty)
- `ci/migration/golden-screenshots/legacy/` (initially empty)
- `ci/no-business-logic-in-swift.sh`
- `ci/ui-copy-fidelity.sh`
- `.github/workflows/migration-lints.yml` (or local pre-commit
  equivalent)

**Tasks:**
- [ ] `copy-features.sh`: bash script that walks `App/Sources/Features`,
      `cp`s each file into `ios/Podcast/Podcast/Features/<rel>`, appends
      manifest row `legacy_path<TAB>copied_path<TAB>sha256`.
- [ ] `apply-token-swap.swift`: SwiftSyntax CLI. Reads
      `ci/migration/token-swap.toml` (table from
      [`../05-migration-map.md`](../05-migration-map.md) §A). Applies
      AST edits to the copied file.
- [ ] `split-features.swift`: SwiftSyntax CLI. Takes a file path + class
      name; removes the class declaration (preserves comments/whitespace
      around it); preserves View structs untouched.
- [ ] `verify-copy-fidelity.sh`: for every row in manifest.tsv, run
      `git diff legacy_path copied_path | grep -vE 'approved-pattern-regex'`;
      fail if any non-approved diff hunks present.
- [ ] `no-business-logic-in-swift.sh`: greps
      `ios/Podcast/Podcast/Features/` for forbidden classes (see
      [`../00-rules.md`](../00-rules.md) §2); greps non-Capabilities
      Swift for `URLSession`/`URLRequest`/`WebSocket`/`Keychain*`; greps
      for legacy singleton imports; fail on any hit.
- [ ] `ui-copy-fidelity.sh`: alias for the manifest verifier; wires into
      pre-commit.
- [ ] CI: add a job that runs both lints + `xcodebuild` on every PR.

**Quality gates:**
- [ ] Lint scripts run green on the M0 skeleton (no `Features/` yet,
      so the trivial case must pass).
- [ ] Token-swap CLI has unit tests on at least 3 fixture inputs
      (one each of: `AppStateStore` → `KernelModel`,
      `AudioEngine.shared.play(x)` → `model.playEpisode(x.id)`,
      `RAGService.shared.search(q)` → `model.searchTranscripts(q)`).
- [ ] `manifest.tsv` schema documented inside the file.

---

## Sequential integration

Run after all four units land in their worktrees.

- [ ] Merge M0.A first (NMP-side change; codex review per NMP rules).
- [ ] Merge M0.B + M0.C together (iOS skeleton + capabilities).
- [ ] Merge M0.D (tooling).
- [ ] Capture **golden screenshots from the legacy app** for every
      Feature view that will be migrated. Output to
      `ci/migration/golden-screenshots/legacy/`. Commit the images.
- [ ] Migrate exactly one UI file as the smoke test:
      - [ ] `OnboardingView.swift` via `ci/migration/copy-features.sh`.
      - [ ] `apply-token-swap.swift` runs and produces a diff that
            matches approved patterns.
      - [ ] `verify-copy-fidelity.sh` green.
      - [ ] App launches; OnboardingView renders against
            `model.snapshot?.nip46_onboarding` (placeholder).
- [ ] Snapshot test for OnboardingView passes against the legacy
      golden.

---

## Exit checklist

- [ ] M0.A, M0.B, M0.C, M0.D merged.
- [ ] Golden screenshots captured for **all** Feature views (to be
      reused throughout M1–M11).
- [ ] OnboardingView smoke test green.
- [ ] App boots in simulator; kernel actor alive; capability callback
      registered.
- [ ] Lint gates active on every PR.
- [ ] Whats-new entry committed: "Internal: app shell rebuilt on NMP
      framework. No user-facing changes yet." (or skip per AGENTS.md
      "would the user notice?")
- [ ] `WIP.md` entries removed.
- [ ] M1 unblocked.

## Hand-off to M1

M1 can rely on:
- `nmp-app-podcast` crate links cleanly.
- iOS `Podcast.app` builds + launches.
- `KernelBridge` + `KernelModel` ready for new snapshot fields.
- `PodcastCapabilities` dispatcher ready for new namespaces.
- `Keychain` + `Http` capabilities working.
- Migration tooling ready for `cp` + token-swap + lint validation.
- Legacy golden screenshots committed for every view.
