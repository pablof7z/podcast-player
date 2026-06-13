---
type: episode-card
date: 2026-05-15
session: f3b466c6-7791-44b3-b004-aae2066a9019
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/f3b466c6-7791-44b3-b004-aae2066a9019.jsonl
salience: architecture
status: active
subjects:
  - nostr-rust-core
  - event-driven-subscriptions
  - no-polling-invariant
supersedes:
  - 2026-05-15-1-ndkswift-replaces-custom-nostr-websocket-layer
related_claims: []
source_lines:
  - 1-1
  - 117-117
  - 2295-2302
captured_at: 2026-06-12T12:39:29Z
---

# Episode: Nostr code migrated from ad-hoc Swift to Rust core with event-driven-only doctrine

## Prior State

Nostr code was scattered ad-hoc across Swift service files, with potential polling-based patterns. No unified ownership or source-of-truth for Nostr operations.

## Trigger

User directive: move all ad-hoc Nostr code into a Rust side, exclusively event-based — NO POLLING ALLOWED — using nostr-sdk in Rust, with ../highlighter as reference code.

## Decision

Created `podcastr-core` Rust crate (~3500 LOC, 9 modules) using `nostr-sdk 0.44.1` with UniFFI 0.29 bindings. All Nostr operations now go through a `Router` trait + single subscription notification pump in `nostr_runtime.rs`. Swift wrappers (`PodcastrCoreBridge` singleton + delta router) delegate entirely to Rust. NIP-42 AUTH handled automatically by nostr-sdk.

## Consequences

- Rust core is now source-of-truth for all Nostr relay, subscription, publishing, and identity operations
- Polling is architecturally prohibited: the only way to receive events is via the Router subscription callback
- Swift layer is thin FFI glue — no business logic remains on the Swift side for Nostr
- 6 open FIXMEs remain for full parity (episode metadata fields, signer key load, observer wiring, tags on PeerMessageRecord and republishAgentProfile)
- UniFFI 0.29 + cdylib/staticlib build pipeline is now a project invariant

## Open Tail

- PodcastEpisodeRecord missing publishedAt, imageUrl, transcript MIME type
- Full end-to-end NIP-46 signer pairing flow (QR rendered in simulator but untested with real signer)

## Evidence

- transcript lines 1-1
- transcript lines 117-117
- transcript lines 2295-2302

