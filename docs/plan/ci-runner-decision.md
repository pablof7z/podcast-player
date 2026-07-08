# CI Runner Decision — `Build and Test` gate

Source: issue #752 — Investigate replacing the self-hosted `Build and Test`
GitHub Actions runner. This is the decision document the issue asks for; it
records the evidence, the recommendation, the migration plan, and the reason
we keep what we keep.

## TL;DR recommendation

Move the per-PR `Build and Test` gate to GitHub-hosted `macos-26` (ARM64,
free for public repos), split into a fast required **unit-test** job and a
slower non-blocking **UI-test** job. Keep the self-hosted runner only for
TestFlight archive/upload where signing secrets and a stable keychain are
required.

This eliminates the single-runner queue that blocked #746–#749 (45–78 min
waits) at zero marginal cost (the repo is public, so GitHub-hosted macOS
minutes are free), and preserves branch-protection coverage by replacing the
single `Build and Test` context with `Build and Test (unit)`.

## Evidence

### Current `Build and Test` behavior (inventory)

| Requirement | Source | Self-hosted today |
|---|---|---|
| Xcode 26.x + iOS 26 simulator SDK | `Project.swift` (`deploymentTarget = .iOS("26.0")`), CI log shows `iPhoneSimulator26.2.sdk` | Xcode.app default at `/Applications/Xcode.app` |
| Tuist generate | `ci_scripts/bootstrap_project.sh` | installs via `install.tuist.io` if missing |
| Rust core for `aarch64-apple-ios-sim` | `ci_scripts/run_tests.sh:41` (`cargo build --target aarch64-apple-ios-sim -p nmp-app-podcast`) | cargo present |
| SwiftPM packages incl. `secp256k1.swift` plugin | `run_tests.sh` passes `-skipPackagePluginValidation` everywhere | plugin trust flag is already wired through every `xcodebuild` invocation |
| Simulator sharding with erase-between-chunks | `run_tests.sh:181–223`, `reset_sim` | uses `xcrun simctl erase/boot/bootstatus` |
| Simulator selection | `run_tests.sh:101–113` prefers a sim whose name ends in ` ci`, falls back to any available iPhone | runner has a purpose-built `iPhone ... ci` simulator (UDID `AABC1FE9-…`) |
| LiteRT-LM SwiftPM disable for sim | `.github/workflows/test.yml` step touches `.ci-disable-litertlm-package` | handled |
| Caches | none declared in `test.yml` for the `test` job; relies on runner-local `~/Library/Developer/Xcode/DerivedData` and `$PWD/Derived/PackageCache` | warm across runs because the runner is persistent |
| Secrets | none used by `test` job | n/a |
| Hardware assumptions | ARM64 macOS, enough RAM for sharded UI tests on a fresh simulator | self-hosted `Pablos-Server-podcast` (ARM64, online, busy) |

The `test` job uses **no repo secrets** and has **no signing/keychain needs**
— those live only in `testflight.yml`'s `deploy` job
(`install_signing_assets.sh`, `archive_and_upload.sh`).

### Self-hosted queue + exec times (2026-07-08)

All times from `gh run view --json jobs` for the `Build and Test` job in
workflow `test.yml`.

| Run | Event | BnT start | BnT end | Queue | Exec |
|---|---|---|---|---|---|
| 28904334888 (#737 push) | push main | 22:54:29 | 23:34:23 | ~0 | 39m54s |
| 28905259805 (#742 PR) | PR | 23:34:25 | 00:11:26 | ~0 (prev freed) | 37m01s |
| 28909332823 (#744 push) | push main | 00:51:43 | 01:31:08 | ~0 | 39m25s |
| 28910594098 (#745 PR) | PR | 01:31:10 | 02:22:33 | ~0 (prev freed) | 51m23s |
| 28912889334 (#745 push) | push main | 02:23:22 | 03:15:55 | ~0 | 52m33s |
| 28913894762 (#746 PR) | PR | 04:08:28 | 05:03:07 | ~78m (queued 02:50, waited for #745 push) | 54m39s |
| 28918879156 (#747 push) | push main | 05:04:57 | 05:58:45 | ~0 | 53m48s |
| 28919588698 (#748 PR) | PR | 05:58:47 | 06:53:09 | ~0 (prev freed) | 54m22s |
| 28923611006 (#748 push) | push main | 06:53:38 | 07:44:24 | ~0 | 50m46s |
| 28923873519 (#749 PR) | PR | 07:44:27 | 08:34:51 | **45m31s** (queued 06:58:56, waited for #748 push) | 50m24s |

Key observations:

- Execution time is stable at **~50–55 min** (build + Rust core + 4 UI
  shards with inter-chunk simulator erases). The `timeout-minutes: 55` is
  well-calibrated.
- Queue time is **0 only when the runner is free**; when a main push and a
  PR land close together, the second run waits the full ~50 min of the
  first. PR #749 waited 45m31s purely because #748's main-push BnT was
  still on the runner. PR #746 waited ~78 min for the same reason.
- With a single self-hosted runner and a multi-agent merge cadence, the
  queue is the bottleneck — not execution. Two concurrent PRs + a main
  push guarantee one waits.
- Within-job step breakdown (run 28923873519): checkout ~2s, bootstrap
  (tuist generate) ~34s, `cargo build` for the sim core ~1m42s, SwiftPM
  resolve ~7s, then four `xcodebuild test` chunks. The first chunk
  (build + unit + light UI) is ~12m; subsequent UI chunks are ~10m each
  after the first build product is reused.

### GitHub-hosted macOS runners available

`actions/runner-images` (verified 2026-07-08) ships these macOS labels:

| Label | Arch | OS | Xcode | Cost for public repo |
|---|---|---|---|---|
| `macos-26` / `macos-26-xlarge` | arm64 | macOS 26.4 | 26.0.1–26.6 (default 26.5) | **free** |
| `macos-26-intel` / `macos-26-large` | x64 | macOS 26 | 26.0.1–26.6 | free |
| `macos-latest` / `macos-15` / `macos-15-xlarge` | arm64 | macOS 15 | 15.x | free |
| `macos-15-large` / `macos-15-intel` | x64 | macOS 15 | 15.x | free |

GitHub billing doc (verified 2026-07-08): "The use of standard
GitHub-hosted runners is free: in public repositories; for GitHub Pages;
for Dependabot." `macos-26` is a **standard** runner (the `-xlarge` /
`-large` suffixes are the larger-runner SKUs and are always billed, even
for public repos; the base `macos-26` label is the free standard one).

`macos-26-arm64-Readme.md` confirms:
- Xcode 26.0.1 through 26.6 installed, default `/Applications/Xcode.app`
  → 26.5. Our `Project.swift` deployment target `.iOS("26.0")` is
  satisfied by the 26.x SDK.
- iOS 26.0–26.5 simulator runtimes installed (iPhone 17, 17 Pro, 17 Pro
  Max, 17e, iPhone Air, iPad variants). `run_tests.sh`'s fallback
  "any available iPhone" will find one without the ` ci` suffix.
- Rustup/Cargo 1.96 preinstalled → `cargo build --target
  aarch64-apple-ios-sim` works out of the box.
- Xcode Command Line Tools, `xcodebuild`, `xcrun simctl` all present.

The repo is public (`gh api repos/pablof7z/podcast-player` →
`private: false`, `owner.type: User`), so GitHub-hosted macOS minutes are
free and unmetered.

### Comparison

| Dimension | Self-hosted today | `macos-26` hosted |
|---|---|---|
| Queue time | 0 when idle, **45–78 min** when contended | typically <2 min (GitHub pool) |
| Execution time | ~50–55 min (warm caches) | ~55–70 min expected (cold SPM/cargo per run; offset by `actions/cache` warming across PRs) |
| Reliability | one machine = single point of failure; a wedged DerivedData halts all PRs | GitHub-managed pool; ephemeral VM per job, no cross-run state wedges |
| Cache strategy | implicit, runner-local `~/Library/Developer/Xcode/DerivedData` + `$PWD/Derived/PackageCache`; warm across runs | explicit `actions/cache` for `~/Library/Developer/Xcode/DerivedData`, `Derived/PackageCache`, `~/.cargo/registry`, `~/.cargo/git`; cold on first run, warm on subsequent PRs for the same `Cargo.lock` + SPM resolved pin |
| Maintenance burden | runner OS/Xcode upgrades, simctl cleanup, plugin-trust read-only-file healing, machine online time | zero — GitHub rotates the image weekly |
| Cost | self-hosted (free, but the machine is Pablo's) | free (public repo, standard runner) |
| Security / secrets | `test` job uses none; `deploy` uses signing certs + App Store Connect key | `test` job on hosted runners uses none → no secret exposure; `deploy` stays self-hosted, so signing secrets never touch a hosted runner |
| Branch protection | single `Build and Test` context | replace with `Build and Test (unit)` (required) + `Build and Test (ui)` (non-blocking) |
| `-skipPackagePluginValidation` | already passed on every `xcodebuild` | preserved — the flag is in `run_tests.sh`, not runner-specific |
| Simulator ` ci` purpose-built sim | used by `run_tests.sh` | not present on hosted; the script's fallback ("any available iPhone") already handles this — verified the fallback branch exists at `run_tests.sh:104–106` |

### Split viability

`run_tests.sh` already separates the unit suite + light UI (chunk 0) from
the heavy UI shards (chunks 1–3). `SKIP_UI_TESTS=1` already runs only the
unit suite (used by `testflight.yml`). This means the split is a workflow
change, not a script rewrite:

- **Required, blocking:** `Build and Test (unit)` —
  `SKIP_UI_TESTS=1 ./ci_scripts/run_tests.sh` on `macos-26`. Expected
  ~15–20 min (build + Rust core + unit suite, no UI shards, no inter-chunk
  sim erases). This is the gate that replaces the current `Build and Test`
  branch-protection context.
- **Non-blocking, informational:** `Build and Test (ui)` — full
  `./ci_scripts/run_tests.sh` on `macos-26`, `continue-on-error: true`,
  posts a status check but is not required. Expected ~50–70 min. Runs in
  parallel with the unit gate so it does not extend the critical path.
- **Nightly (optional, future):** if the UI lane proves flaky on hosted
  runners, move it to a scheduled nightly on `main` and surface a
  dashboard. Not needed for the migration.

### Branch-protection compatibility

Current required contexts include `Build and Test`. The migration replaces
that single context with `Build and Test (unit)`. The branch-protection
API call is a one-line context swap; the existing
`docs/plan.md` "Validation gate" entry and `docs/BACKLOG.md`
`p0-validation-gate` item get updated in the same PR to name the new
context and record the hosted-runner decision.

UI coverage is preserved (the `Build and Test (ui)` job still runs on
every PR) but is non-blocking, so a flaky hosted-simulator UI run cannot
block a merge that has a green unit gate, green Rust/Android gates, and
green headless-e2e. The TestFlight `test` job in `testflight.yml` already
runs `SKIP_UI_TESTS=1` and is unaffected.

## Migration plan

1. **Workflow change** — `.github/workflows/test.yml`:
   - Replace the single `test` job with two jobs on `macos-26`:
     - `test-unit`: `SKIP_UI_TESTS=1 ./ci_scripts/run_tests.sh`, required,
       `timeout-minutes: 30`.
     - `test-ui`: `./ci_scripts/run_tests.sh` (full), `continue-on-error:
       true`, `timeout-minutes: 70`, name `Build and Test (ui)`.
   - Add `actions/cache` steps for:
     - `~/Library/Developer/Xcode/DerivedData/Podcastr-*` (keyed on
       `Project.swift` + `Cargo.lock` + `.package.resolved`),
     - `Derived/PackageCache` + `Derived/SourcePackages` (same key),
     - `~/.cargo/registry` + `~/.cargo/git` (keyed on `Cargo.lock`,
       restore-key prefix for partial hits — same pattern as the existing
       ubuntu cargo caches).
   - Keep the `concurrency: cancel-in-progress: true` group so a fast
     merge cadence still cancels stale runs.
   - Keep `.ci-disable-litertlm-package` touch before bootstrap.
   - Keep `bootstrap_project.sh` + `run_tests.sh` unchanged — they already
     handle a clean image (Tuist auto-installs, `xcodebuild` resolves
     packages, `simctl` falls back to any available iPhone).
2. **Branch protection** — swap the `Build and Test` required context for
   `Build and Test (unit)` via `gh api -X PUT
   repos/pablof7z/podcast-player/branches/main/protection` (or the repo
   settings UI). Keep all other required contexts unchanged.
3. **TestFlight unchanged** — `testflight.yml`'s `test` and `deploy` jobs
   stay on `self-hosted` because `deploy` needs the signing keychain. The
   `test` job there is already `SKIP_UI_TESTS=1` and is gated by the
   version-bump check, so it runs rarely and does not contribute to the
   per-PR queue.
4. **Self-hosted runner** — keep `Pablos-Server-podcast` online for
   TestFlight. Optionally remove the `self-hosted` label from the Test
   workflow's `runs-on` once the hosted lane is green for a week.
5. **Docs** — update `docs/plan.md` "Validation gate" and
   `docs/BACKLOG.md` `p0-validation-gate` to name the new context and
   record the decision. Link this document from `docs/plan.md`.

### Validation performed by this PR

- `git diff --check` clean.
- Workflow YAML lint: `actionlint` (if available) or a dry-run
  `gh workflow view test.yml` to confirm the file parses.
- One PR-driven run of both new jobs on `macos-26` to confirm:
  - `cargo build --target aarch64-apple-ios-sim` succeeds on the hosted
    image,
  - `tuist generate` succeeds (auto-install path),
  - `xcodebuild test` with `-skipPackagePluginValidation` resolves
    `secp256k1.swift`'s `SharedSourcesPlugin` without interactive trust,
  - the simulator fallback picks an iPhone 17/Pro on the hosted image,
  - `actions/cache` restores on the second run.
- After the first hosted run is green, swap the branch-protection context
  and merge.

## Why not fully retire self-hosted

The TestFlight `deploy` job cannot move to a hosted runner without
exposing the Apple Distribution certificate, provisioning profiles, and
App Store Connect API key to a GitHub-hosted VM. Self-hosted keeps those
secrets on Pablo's machine, where the keychain is already configured and
`install_signing_assets.sh` / `cleanup_signing_assets.sh` manage the
lifecycle. The `test` job in `testflight.yml` shares the runner with
`deploy` and is already version-gated to run only on actual releases, so
it does not contribute to the per-PR queue that motivated #752.

## Subjective decisions / tradeoffs / assumptions

- **Assumption:** `macos-26` (standard, ARM64) is available to this
  public User-owned repo at no cost. Verified via the billing doc and the
  repo's `private: false` flag. If the account ever flips to private, the
  free minutes quota (2,000/mo on Free, 3,000/mo on Pro) would be
  consumed at ~$0.062/min for macOS — ~$3 per 50-min run — and the
  hosted lane would need a budget review. The decision document records
  this so the lane can be reverted if billing changes.
- **Tradeoff:** cold first-run on hosted (no warm DerivedData) adds
  ~5–10 min to the first PR after a cache miss. `actions/cache` warming
  closes this after one run; the cache key includes `Cargo.lock` +
  `.package.resolved` + `Project.swift` so dependency bumps are the only
  cache-invalidating events.
- **Tradeoff:** the UI lane becomes non-blocking. This is deliberate: a
  flaky hosted-simulator UI run should not block a merge that is green
  on unit, Rust, Android, and headless-e2e. The TestFlight `test` job
  already runs `SKIP_UI_TESTS=1`, so release gating is unaffected. If UI
  regressions slip through, the nightly lane (future work) catches them
  before the next release.
- **Decision:** keep `run_tests.sh` and `bootstrap_project.sh` unchanged.
  They already handle a clean image. The ` ci` simulator preference is a
  no-op on hosted (no such sim exists) and the fallback branch handles
  it. This avoids forking the scripts per runner.
- **Decision:** do not use `macos-26-xlarge` / `macos-26-large` — those
  are larger-runner SKUs and are always billed, even for public repos.
  The standard `macos-26` label is the free one and is sufficient for a
  ~50-min UI suite.