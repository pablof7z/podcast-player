---
type: episode-card
date: 2026-06-06
session: 52b667b5-ed45-479e-a960-1baeefbbdf03
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/52b667b5-ed45-479e-a960-1baeefbbdf03.jsonl
salience: direction
status: active
subjects:
  - ios-shake-feedback
  - nmp-extensions
  - shake-to-feedback
supersedes: []
related_claims: []
source_lines:
  - 253-259
captured_at: 2026-06-12T13:24:17Z
---

# Episode: ios-shake-feedback should become an NMP extension, not standalone package

## Prior State

ios-shake-feedback was a self-contained SwiftPM package with its own Nostr identity and relay client, independent of the NMP app framework.

## Trigger

User directed that ios-shake-feedback should be an NMP "extension" or plugin that plugs into existing NMP apps, rather than a standalone package.

## Decision

Filed issue (pablof7z/ios-shake-feedback#1) to redesign the package: drop the self-contained Nostr identity and relay client, replace with a single register(with: nmpApp, relays: [...]) entry point so any NMP app gets shake-to-feedback by adding the package and making one call.

## Consequences

- ios-shake-feedback will lose its self-contained identity/relay stack and become dependent on NMP app infrastructure.
- Any NMP app will be able to opt into shake-to-feedback with minimal integration code.
- The current standalone SwiftPM architecture is now legacy/direction-to-be-replaced.

## Open Tail

- The actual implementation of the NMP extension architecture has not been done — only the issue exists.
- The xcframework's Rust core (ShakeFeedbackCore) may need to be restructured as an NMP crate rather than a standalone binary.

## Evidence

- transcript lines 253-259

