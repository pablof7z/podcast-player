---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: active
subjects:
  - android-ci
  - ffi-guard
  - jint-suffix
supersedes:
  - 2026-06-12-4-android-rust-cross-compile-break-invisible
  - 2026-06-12-5-android-cfg-gated-jni-surface-invisible
related_claims: []
source_lines:
  - 4437-4438
  - 4450-4482
  - 4710-4720
captured_at: 2026-06-12T14:47:13Z
---

# Episode: Android cross-compile invisibly broken — permanent CI guard added

## Prior State

PR #387 introduced `ffi_guard` fallback closures with invalid Rust numeric literal suffixes (`0jlong`, `0jint`, `-1jint`). These compiled on the host but broke Android cross-compilation silently — there was no CI job checking the Android target.

## Trigger

The per-domain work needed Android changes, and the cross-compile failure surfaced during the `android-check` CI job validation.

## Decision

Fix the three invalid suffixes to `0 as jlong`, `0 as jint`, `-1 as jint`. Add a permanent `android-check` CI job (`cargo check --target aarch64-linux-android` with NDK) that runs on every PR, closing the invisible-breakage class.

## Consequences

- Android cross-compile can't silently rot again — the CI gate catches it on every PR
- The `ffi_guard` pattern is now validated for both host and Android targets

## Open Tail

*(none)*

## Evidence

- transcript lines 4437-4438
- transcript lines 4450-4482
- transcript lines 4710-4720

