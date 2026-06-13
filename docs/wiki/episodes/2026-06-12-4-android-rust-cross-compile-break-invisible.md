---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - android-jint-fix
  - cfg-gated-ci-gap
  - android-cross-compile
supersedes: []
related_claims: []
source_lines:
  - 4372-4374
  - 4445-4482
captured_at: 2026-06-12T14:21:59Z
---

# Episode: Android Rust cross-compile break invisible to CI

## Prior State

Android-targeted Rust code (`#[cfg(target_os = "android")]` modules) was never compiled by CI. Invalid numeric literal suffixes (`0jint`, `-1jint`, `0jlong`) introduced by #387's `ffi_guard` in `android.rs` were invisible broken code that compiled fine on macOS but would fail on the Android target.

## Trigger

Cycle-4 planning verified the break: `apps/nmp-app-podcast/src/android.rs:231` `|| 0jint` and `:416` `|| -1jint` — invalid Rust numeric-literal suffixes. No CI workflow compiled an Android target (`test.yml`/`migration-lints.yml`/`testflight.yml` only).

## Decision

Fix the 3 invalid literal suffixes (`|| 0 as jlong`, `|| 0 as jint`, `|| -1 as jint`) and add a permanent `android-check` CI job: `cargo check -p nmp-app-podcast --target aarch64-linux-android` on `ubuntu-latest` with NDK toolchain. This closes the entire 'Android-only Rust breakage' class, not just this literal.

## Consequences

- The 3 invalid suffixes are fixed; grep confirms no remaining `jint`/`jlong`/`jobject` bare suffixes
- Every future PR now compiles the cfg-gated JNI surface against the Android target — the invisible-breakage class is permanently closed
- CI job requires NDK setup (ring/aws-lc-sys/secp256k1-sys have C build scripts needing `aarch64-linux-android-clang`)

## Open Tail

*(none)*

## Evidence

- transcript lines 4372-4374
- transcript lines 4445-4482

