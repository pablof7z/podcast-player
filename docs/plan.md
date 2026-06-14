# Plan

Detailed implementation plans live under `docs/plan/` and are linked from this file.

## Active Work

| Work | State | Source |
|---|---|---|
| NMP feature parity hardening and scaffold burn-down. | Active | `docs/plan/nmp-feature-parity.md` |
| Rust-kernel migration v2 (PlaybackState pure renderer → Compat dir deletion). | Active | `docs/plan/migration-v2.md` |
| NIP-F4 publishing/signing completion for owned publishing/discovery. | P0 | `docs/plan/pod0-nostr-publishing.md` |
| Android feature wave 1 (subscribe/search/episode detail) + parity matrix. | Active | `docs/plan/android-parity.md` |
| TUI feature parity foundation and terminal surface expansion. | Active | `docs/plan/tui-parity.md` |
| TUI live agent validation with Ollama Cloud. | Active | `docs/plan/tui-agent-live-validation.md` |
| Shared LLM provider transport and typed task intents. | Active | `docs/plan/shared-llm-task-architecture.md` |
| Optimistic subscribe + async HTTP capability (instant subscribe, off-thread feed hydration). | Active | `docs/plan/optimistic-subscribe-async-http.md` |

## Planning Files

- `docs/BACKLOG.md` - tactical queue, active violations, and follow-up work.
- `WIP.md` - active branches/worktrees only.
- `docs/plan/nmp-feature-parity.md` - canonical feature-parity execution status and scaffold burn-down instructions.
- `docs/plan/migration-v2.md` - ordered milestone plan (M0–M8) for completing the Rust-kernel migration.
- `docs/plan/pod0-nostr-publishing.md` - NIP-F4 protocol correction and publishing/discovery plan.
- `docs/plan/android-parity.md` - Android feature-parity status matrix (Tier 1-4) and the subscribe/search/episode-detail wave.
- `docs/plan/tui-parity.md` - Terminal-client parity matrix and staged implementation plan.
- `docs/plan/tui-agent-live-validation.md` - live tmux scenario inventory and validation log for agentic TUI workflows.
- `docs/plan/shared-llm-task-architecture.md` - provider transport, model routing, and typed task-intent ownership contract across platforms.

## Active State

| Area | Status |
|---|---|
| NMP dependency pin | `0.6.2` crates are pinned to rev `fbc0155031fdf862fa47673c5211fc3eebc3863c` in `Cargo.toml`; PR #488 replaced the non-portable `/tmp/nmp-at-ac7e307e` path patch with reproducible `vendor/nmp-blossom`, and PR #498 removed the temporary `vendor/nmp-core` fork after the ADR-0055 `publish_ver` fix landed upstream. `nmp-feedback` is pinned in lockstep at `630d1a9f0e3256c9fe0ab1480f2a35e058f8c9e0`. Local blocker `pablof7z/podcast-player#479` is closed. Upstream `pablof7z/nostr-multi-platform#1408` and `#1412` remain upstream cleanup/dependency notes, but current podcast-player `main` no longer carries an app-local `nmp-core` workaround. |
| Feature parity | Not achieved — many merged PRs are scaffolds or heuristics, not full original-app behavior. |
| Legacy app deletion | Blocked — `App/Sources/` remains the reference implementation until all parity exits pass. |
| Parked iOS shell | Deleted — there is no `ios/` tree on current `main`; remaining parity debt lives in `App/Sources/` Swift policy/fallback code and the cross-platform surfaces listed in `docs/BACKLOG.md`. |
| NIP-F4 Keychain flip | Cancelled — `podcast-keys.json` is the canonical and final store for per-podcast secrets. No Keychain migration. |
| Validation gate | Partially established — branch protection requires diff hygiene, migration PR-description lint, Rust workspace, Swift bridge codegen drift, Android Kotlin/unit tests, Android cross-compile, and headless e2e. The full iOS simulator `Build and Test` lane is still not a required merge gate. PR #497 fixed the known playback UI blockers with canonical seeded download paths, UI-test lifecycle teardown, off-main-safe Now Playing artwork, and hardened playback reopen/launch-metric flows; focused local validations passed for those failures. Wait for a clean main-equivalent full-lane run before adding `Build and Test` back to required branch protection. Feature parity is still not achieved; each code slice still needs focused local validation plus the required merge gate. The old `nmp-blossom` packaging blocker is resolved on `main`; the `publish_outbox` projection-rev issue is carried by the upstream-pinned NMP rev from PR #498, not by a local `nmp-core` fork. |

## Next Execution Order

1. Burn down feature-parity scaffolds — replace AI/platform scaffolds with real logic, one PR per backlog item.
2. Burn down remaining Swift policy/fallback code in `App/Sources/` — replace each business decision with Rust-backed snapshot/action behavior.
3. Observe a clean main-equivalent iOS simulator `Build and Test` run after PR #497, then add it back to required branch protection.
4. Re-run full validation and only then mark feature-parity done.
