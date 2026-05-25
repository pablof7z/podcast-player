# Reference materials

Files in NMP and Podcastr to study or copy. Cited from milestone pages.

## NMP — what to read

Doctrine + product spec (read in this order before any work):
1. `/home/pablo/Work/nostrmultiplatform/AGENTS.md` — non-negotiable rules.
2. `/home/pablo/Work/nostrmultiplatform/docs/aim.md` — north star.
3. `/home/pablo/Work/nostrmultiplatform/docs/product-spec/overview-and-dx.md` §1.5 — D0–D10.
4. `/home/pablo/Work/nostrmultiplatform/docs/decisions/0009-app-extension-kernel-boundary.md`.
5. `/home/pablo/Work/nostrmultiplatform/docs/decisions/0010-generated-app-enum-vs-type-erased-registry.md`.
6. `/home/pablo/Work/nostrmultiplatform/docs/design/framework-magic.md`.
7. `/home/pablo/Work/nostrmultiplatform/docs/plan.md` and `docs/BACKLOG.md` — current state of NMP work.

## NMP — what to copy

The Chirp iOS app is the reference model. Copy structure, adapt for
Podcastr:

- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/Chirp/Bridge/KernelBridge.swift`
  (1895 LOC). **Split on copy** into ≤300 LOC files:
  - `KernelBridge.swift` — public API, dispatch entry points.
  - `KernelBridge+Decode.swift` — JSON decoding.
  - `KernelBridge+Callbacks.swift` — C callback boxing.
  - `KernelBridge+Types.swift` — Decodable structs.
  - `KernelBridge+Actions.swift` — typed action helpers.
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/Chirp/Bridge/KernelModel.swift`
  (640 LOC). Adapt: replace `chirp*` accessors with `podcast*`
  accessors and `model.snapshot?.<podcast-field>` patterns.
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/Chirp/Bridge/Generated/KernelTypes.generated.swift`
  (schemars-generated; regenerate for podcast types).
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/Chirp/Capabilities/ChirpCapabilities.swift` (rename for podcast).
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/Chirp/Capabilities/KeychainCapability.swift` (copy verbatim; add BYOK namespaces).
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/Chirp/Capabilities/HttpCapability.swift` (copy and widen — see [`03-capabilities.md`](03-capabilities.md) §5.9).
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/project.yml` (adapt bundle ID, lib name, signing).
- `/home/pablo/Work/nostrmultiplatform/apps/chirp/nmp-app-chirp/Cargo.toml` (template).
- `/home/pablo/Work/nostrmultiplatform/apps/chirp/nmp-app-chirp/src/{lib.rs, ffi/*}` (template).
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/Chirp/App/{ChirpApp,RootShell}.swift` (mirror lifecycle + tab structure).

## Podcastr — files to preserve verbatim

- `/home/pablo/Work/podcast/App/Resources/Assets.xcassets`.
- `/home/pablo/Work/podcast/App/Resources/whats-new.json`.
- `/home/pablo/Work/podcast/App/Resources/Podcastr.entitlements` (audit
  `keychain-access-groups` — see R6 in [`07-risks.md`](07-risks.md)).
- `/home/pablo/Work/podcast/App/Sources/Design/*.swift` — pure UI
  utilities; copy verbatim (audit `DateExtensions.swift` for policy).
- `/home/pablo/Work/podcast/App/Sources/Features/**/*.swift` — copy via
  `ci/migration/copy-features.sh` per [`00-rules.md`](00-rules.md) §3.

## Podcastr docs (current spec)

- `/home/pablo/Work/podcast/docs/spec/PRODUCT_SPEC.md` — product spec
  entry point.
- `/home/pablo/Work/podcast/docs/spec/PROJECT_CONTEXT.md` — vision
  summary.
- `/home/pablo/Work/podcast/AGENTS.md` — Podcastr's own discipline
  (typography, file size, whats-new).

## Tooling references

- `ci/migration/copy-features.sh`, `apply-token-swap.swift`,
  `split-features.swift`, `verify-copy-fidelity.sh` — to be authored
  in M0.
- `ci/no-business-logic-in-swift.sh`, `ci/ui-copy-fidelity.sh` — lint
  gates, to be authored in M0.
- `swift-snapshot-testing` — golden screenshot framework. Capture
  legacy goldens in M0.

## Test references

- `/home/pablo/Work/nostrmultiplatform/crates/nmp-testing/` — mock
  relay harness, scenarios, doctrine lint.
- `/home/pablo/Work/nostrmultiplatform/ios/Chirp/ChirpTests/SmokeScenariosTests.swift`
  — model for `PodcastTests/` scenario tests (shared kernel, real
  FFI, real relays).

## How to run codex review

`codex exec --sandbox workspace-write [prompt]`. Used post-merge on
NMP-side PRs per existing NMP convention.
