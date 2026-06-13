---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - ci-doctrine
  - android-build
  - cfg-gated-code
supersedes: []
related_claims: []
source_lines:
  - 4445-4483
captured_at: 2026-06-12T13:58:37Z
---

# Episode: Android cross-compile CI guard — permanent check for cfg-gated JNI surface

## Prior State

Android-only Rust code (`#[cfg(target_os = "android")]`) had no CI coverage. The existing test/migration-lint/testflight workflows only compiled for the host target, so Android-specific breakages (invalid `jint`/`jlong` suffixes from #387's ffi_guard) rotted invisibly

## Trigger

Discovered three invalid Rust numeric-literal suffixes (`0jlong`, `0jint`, `-1jint`) in `android.rs` that prevented Android cross-compilation — invisible to CI because no workflow compiled the Android target

## Decision

Add a permanent `android-check` CI job: `cargo check -p nmp-app-podcast --target aarch64-linux-android` on ubuntu-latest with NDK toolchain. This closes the entire invisible-breakage class, not just this literal

## Consequences

- Any future breakage of the cfg-gated JNI surface will be caught on PR
- The three invalid suffix sites fixed: `0 as jlong`, `0 as jint`, `-1 as jint`

## Open Tail

*(none)*

## Evidence

- transcript lines 4445-4483

