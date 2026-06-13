---
type: episode-card
date: 2026-06-02
session: 8bfa1b91-b40c-44b3-acb9-245b36f4c841
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8bfa1b91-b40c-44b3-acb9-245b36f4c841.jsonl
salience: root-cause
status: superseded
subjects:
  - ios-linking
  - nmp-app-podcast
  - xcode-build
  - cdylib-vs-staticlib
supersedes: []
related_claims: []
source_lines:
  - 2023-2180
captured_at: 2026-06-12T12:56:22Z
---

# Episode: iOS device crash from linker preferring cdylib over static archive

## Prior State

Xcode linked Rust `nmp_app_podcast` via `-lnmp_app_podcast` flag. The crate's `crate-type = ["staticlib", "rlib", "cdylib"]` (cdylib needed for Android `.so`) caused `cargo build` to emit both `libnmp_app_podcast.a` and `libnmp_app_podcast.dylib`. The linker's `-l` flag prefers `.dylib`, which embeds an absolute Mac install-name path. On iOS device, DYLD cannot resolve that path → immediate crash at launch.

## Trigger

App crashed instantly on iPhone; crash report showed `DYLD: Library not loaded: /Users/.../libnmp_app_podcast.dylib` (SIGABRT, termination namespace DYLD, indicator "Library missing")

## Decision

Replaced unconditional `OTHER_LDFLAGS = "$(inherited) -lnmp_app_podcast"` in both Xcode build configs with sdk-conditional entries: `OTHER_LDFLAGS[sdk=iphoneos*]` points at the explicit `.a` file path, bypassing the dylib entirely; simulator keeps `-lnmp_app_podcast` (safe because simulator runs on macOS where the dylib path resolves).

## Consequences

- iOS device builds now statically link the Rust library; no dylib runtime dependency
- The cdylib crate type is preserved for Android JNI — no source change needed
- Future cargo builds that re-emit the .dylib will not re-introduce the crash, since the explicit .a path in OTHER_LDFLAGS takes priority for device builds

## Open Tail

*(none)*

## Evidence

- transcript lines 2023-2180

