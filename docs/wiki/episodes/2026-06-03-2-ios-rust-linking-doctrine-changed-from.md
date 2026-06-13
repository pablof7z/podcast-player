---
type: episode-card
date: 2026-06-03
session: 6706236b-c94a-4458-aa7b-6f71098aa55b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/6706236b-c94a-4458-aa7b-6f71098aa55b.jsonl
salience: architecture
status: superseded
subjects:
  - ios-build-pipeline
  - rust-linking
  - shake-feedback-core
supersedes:
  - 2026-06-02-1-ios-device-crash-from-linker-preferring
related_claims: []
source_lines:
  - 2027-2077
  - 2196-2210
  - 2441-2500
  - 2700-2784
  - 2998-3078
captured_at: 2026-06-12T13:04:25Z
---

# Episode: iOS Rust linking doctrine changed from static .a to signed dylib embedding

## Prior State

Build pipeline deleted the Rust .dylib after cargo build, forcing Xcode to link the static .a — documented as required doctrine to avoid Mac-absolute install-name paths causing device crashes

## Trigger

Adding LiteRTLM (with `-all_load` linker flag) caused duplicate-symbol conflicts between `libnmp_app_podcast.a` and `shake_feedback_core.a` — both static archives contain the full Rust std, compiler_builtins, memchr, serde_json, etc., and `-all_load` forces all symbols from both, producing ~168 duplicate-symbol errors

## Decision

Changed doctrine: keep the .dylib (linker prefers it over .a, avoiding static symbol conflicts), fix its install name to `@rpath/libnmp_app_podcast.dylib` via `install_name_tool`, embed it into `Podcastr.app/Frameworks/` via an Xcode build phase script, and codesign it with the development certificate using `codesign -s <hash>`

## Consequences

- Duplicate-symbol conflict between nmp_app_podcast and shake_feedback_core is eliminated
- The dylib must be properly codesigned or iOS rejects it at launch (crash)
- Build phase `Embed Rust Dylib` added to Project.swift handles copy + install_name_tool + codesign
- Old wiki note about 'must use static .a' is now outdated and incorrect
- Simulator fat-binary slice of shake_feedback_core still has unstripped std objects but doesn't affect device builds

## Open Tail

- The XCFramework for shake_feedback_core still bundles its own Rust std — a future cleanup could rebuild it without std to reduce binary size
- Ad-hoc codesigning (`--sign -`) was insufficient; must use the actual development certificate fingerprint

## Evidence

- transcript lines 2027-2077
- transcript lines 2196-2210
- transcript lines 2441-2500
- transcript lines 2700-2784
- transcript lines 2998-3078

