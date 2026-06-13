---
type: episode-card
date: 2026-06-10
session: 38f8143c-c90d-49e3-a8fa-8d5ca17ac319
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/38f8143c-c90d-49e3-a8fa-8d5ca17ac319.jsonl
salience: root-cause
status: superseded
subjects:
  - widget-snapshot
  - ffi-decode
  - snake-case-contract
supersedes: []
related_claims: []
source_lines:
  - 1326-1329
  - 1402-1428
  - 1548-1551
captured_at: 2026-06-12T13:48:00Z
---

# Episode: Embedded WidgetSnapshot CodingKeys conflict with convertFromSnakeCase decoder

## Prior State

PR #366 added explicit snake_case CodingKeys on the embedded WidgetSnapshot Swift type, assuming they were needed for JSON serialization of the kernel projection

## Trigger

Live iOS simulator verification showed every PodcastUpdate frame failing to decode: DecodingError.keyNotFound for 'is_playing' — the explicit CodingKeys and the bridge's .convertFromSnakeCase strategy are mutually exclusive; the decoder auto-maps is_playing → isPlaying but the manual CodingKeys force it back to is_playing, then the required Bool key vanishes

## Decision

Remove all explicit CodingKeys from the embedded WidgetSnapshot type; rename nowPlayingArtworkURL → nowPlayingArtworkUrl to match convertFromSnakeCase acronym convention; centralize decode logic into KernelDecoding.swift with makeDecoder()/decodePodcastUpdate(from:); add Rust-fixture contract test that proves a plain decoder fails while the bridge decoder succeeds (PR #371)

## Consequences

- All 5 bridge decode sites (push + pull) now route through centralized KernelDecoding, preventing future single-site drift
- The snake_case contract is now doctrinal: Rust emits snake_case JSON, iOS uses .convertFromSnakeCase, embedded types must NOT declare explicit CodingKeys
- A memory file was created documenting this contract to prevent recurrence
- PR #371 was squash-merged to main, unblocking all iOS builds that had frozen library hydration

## Open Tail

- HandoffState was deliberately left with its explicit CodingKeys because it is not embedded in PodcastUpdate (separate NSUserActivity path) — but any future embedded type must follow the no-CodingKeys rule

## Evidence

- transcript lines 1326-1329
- transcript lines 1402-1428
- transcript lines 1548-1551

