---
type: episode-card
date: 2026-06-08
session: 713480e4-3c98-439e-a897-2f41d37acbfd
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/713480e4-3c98-439e-a897-2f41d37acbfd.jsonl
salience: root-cause
status: active
subjects:
  - ios-deploy
  - rust-dylib-linking
  - justfile-recipe
supersedes:
  - 2026-06-03-2-ios-rust-linking-doctrine-changed-from
related_claims: []
source_lines:
  - 1-37
  - 40-70
  - 89-112
  - 122-148
captured_at: 2026-06-12T13:28:00Z
---

# Episode: Fix iOS deploy: keep Rust dylib instead of forcing static link

## Prior State

The `pablo-iphone-deploy` justfile recipe deleted the Rust `.dylib` after `cargo build` to force static `.a` linking, which produced duplicate-symbol linker errors because two Rust static archives each force-load `std` via `-all_load`.

## Trigger

User attempted `just pablo-iphone-deploy` and hit a wall of duplicate `std` symbol errors (plus a secondary app-path bug injecting a stray newline into the install NSURL). Root-cause diagnosis: dylib deletion strategy is fundamentally incompatible with `-all_load` — every `std` symbol appears in both `.a` files.

## Decision

Adopt the PR #255 approach: keep the Rust dylib and let Project.swift's "Fix Rust Dylib Install Name" and "Embed Rust Dylib" build phases handle `@rpath`/embed/codesign. Rewrote the justfile recipe accordingly.

## Consequences

- `just pablo-iphone-deploy` now works end-to-end for device deployment
- Justfile comments explain why deleting the dylib breaks things, preventing accidental reversion
- Fresh derivedData per run prevents stale objects from causing phantom duplicate symbols
- App path is read directly from derivedData products dir, fixing the awk-pipeline newline bug that caused the `%0A` in NSURL
- Build no longer requires the device connected at compile time (`generic/platform=iOS` destination)

## Open Tail

*(none)*

## Evidence

- transcript lines 1-37
- transcript lines 40-70
- transcript lines 89-112
- transcript lines 122-148

