---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - android-jni
  - ci-guard
  - cfg-gated-code
supersedes:
  - 2026-06-12-6-android-cross-compile-ci-guard-permanent
related_claims: []
source_lines:
  - 4450-4482
captured_at: 2026-06-12T14:08:15Z
---

# Episode: Android cfg-gated JNI surface invisible to CI — permanent guard added

## Prior State

#[cfg(target_os = "android")] code could rot invisibly — no CI workflow compiled the Android target. #387's ffi_guard introduced 0jint, -1jint, 0jlong invalid Rust suffixes that broke the Android build without anyone noticing.

## Trigger

The invalid suffixes were discovered while trying to validate Android work. The entire Android Rust JNI surface was uncompiled on any PR, meaning any cfg-gated code change could silently break the Android build.

## Decision

Fix the 3 invalid suffix sites (0jlong → 0 as jlong, 0jint → 0 as jint, -1jint → -1 as jint) and add a permanent android-check CI job (cargo check --target aarch64-linux-android with NDK) so the entire cfg-gated JNI surface compiles on every PR.

## Consequences

- The entire Android JNI surface is compiled on every PR — the invisible-breakage class is closed
- Any future cfg-gated Android code change will be caught by CI
- The source fix (as casts) is unambiguous; the CI job is self-validating

## Open Tail

*(none)*

## Evidence

- transcript lines 4450-4482

