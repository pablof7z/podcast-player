---
type: episode-card
date: 2026-06-09
session: 0964cb48-04df-4b35-9ad9-67cdc6a9d488
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0964cb48-04df-4b35-9ad9-67cdc6a9d488.jsonl
salience: architecture
status: active
subjects:
  - reqwest-tls
  - android-cross-compile
  - rustls-migration
supersedes: []
related_claims: []
source_lines:
  - 41-161
captured_at: 2026-06-12T13:38:33Z
---

# Episode: reqwest dual-TLS eliminated — rustls-only doctrine enforced

## Prior State

reqwest dependency specified rustls-tls feature but omitted default-features = false, so default-tls (→ native-tls → openssl-sys) was also pulled in. The whole codebase otherwise standardized on rustls (tokio-tungstenite, rig-core).

## Trigger

Android APK cross-compilation failed: openssl-sys cannot cross-compile to aarch64-linux-android without vendored OpenSSL or a sysroot.

## Decision

Add default-features = false to the reqwest dependency line, making the crate rustls-only and eliminating the native-tls/openssl-sys dependency entirely.

## Consequences

- Android cross-compilation succeeds without OpenSSL sysroot
- Single TLS backend (rustls) across all platforms and all HTTP-using dependencies
- No behavior change for iOS or TUI — they were already using rustls-tls at runtime

## Open Tail

*(none)*

## Evidence

- transcript lines 41-161

