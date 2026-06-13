---
title: Nostr Podcast Publisher
slug: nostr-podcast-publisher
topic: nostr-protocol
summary: The NIP-19 `naddr` TLV encoder lives in `App/Sources/Services/NIP19.swift`
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-15
updated: 2026-06-12
verified: 2026-05-15
compiled-from: conversation
sources:
  - session:d0447a6c-e8a4-4913-a5bd-cd462c96487a
  - session:f3b466c6-7791-44b3-b004-aae2066a9019
  - session:144a71df-cae7-4a4e-a996-64db4a3bef0b
  - session:c43d5e77-d667-4e71-a574-47aaab5b6a7a
  - session:rollout-2026-05-25T12-53-39-019e5e8d-ec64-74f1-a1b1-91055dcab442
  - session:rollout-2026-05-25T12-53-46-019e5e8e-043d-7dc2-8171-2238de03d145
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Nostr Podcast Publisher

## NIP-19 naddr TLV Encoding

create_podcast and update_podcast return both nostr_event_id (32-byte hex) and naddr (NIP-19 bech32 addressable event identifier) whenever a show event is published, rather than returning only the event ID or npub. (Previously: The `nostrAddr()` for a podcast must return the event ID or podcast pubkey/npub instead of an naddr, superseded — see agent-owned-podcasts.) Swift passes only semantic data (recipient, root, content, channel anchors) to the kernel; Rust constructs all NIP-10 tags and Nostr event structure, so the NIP-19 naddr encoder no longer lives in App/Sources/Services/NIP19.swift. (Previously: The NIP-19 `naddr` TLV encoder lives in `App/Sources/Services/NIP19.swift`; NIP19 only encodes naddr and has no `npub(pubkeyHex:)` helper, contradicting the plan document (`docs/plan/pod0-nostr-publishing.md`) which states it does, superseded — see nostr-rust-ffi.) It encodes TLV type 0 as the full d-tag string in UTF-8 bytes (e.g., `"podcast:guid:<uuid-lowercase>"`), type 2 as the 32-byte pubkey, and type 3 as the kind as a 4-byte big-endian UInt32. NIP-F4 discovery must use kinds 10154/54, remove dTag, and look up episodes by authors:[show.pubkey] rather than relying on a d-tag value in naddr TLV-0. (Previously: The d-tag in TLV-0 must be the full string, not just the UUID, to produce a resolving naddr, superseded — see nip74-episode-events.)

<!-- citations: [^d0447-3] [^144a7-6] [^rollo-183] [^rollo-197] -->
## Retroactive Episode Publishing

The owned-podcast kind:54 backfill (PR #397) moved per-episode publishing from a synchronous Swift loop into kernel-owned self-enqueued dispatches — update_owned detects a private→public flip, then self-dispatches N publish_episode actions via nmp_app_dispatch_action so the actor yields between episodes. (Previously: Retroactive episode publishing uses a sequential loop rather than `TaskGroup` due to Swift 6 concurrency constraints preventing `self` capture in `sending` closures. <!--  -->, superseded — see podcast-app-state.)

republishAgentProfile needs an extra_tags parameter to restore the legacy backend event tag. <!-- [^f3b46-14] -->

## NIP-F4 Event Kinds

The podcast Nostr implementation uses NIP-F4 (kind:10154 for shows, kind:54 for episodes, kind:10064 for author claims) instead of NIP-74 (kind:30074/30075). <!-- [^144a7-1] -->

Show events use kind:10154 with a `description` tag and no d-tag; episode events use kind:54 with an `audio` tag (replacing `imeta`) and no d-tag. <!-- [^144a7-2] -->

Episode GUIDs are the Nostr event ID; shows are identified by pubkey alone with coordinate format `10154:<pubkey>`. <!-- [^144a7-3] -->

## Per-Podcast Keypair and Author Claims

Creating a private show does not require a Nostr signing key — when visibility is .private, ownerPubkeyHex falls back to an 'agent-private' sentinel value; per-podcast secp256k1 keys are registered as non-active NMP accounts only when events are actually published. (Previously: Each podcast has its own Nostr keypair; the agent publishes a kind:10064 author claim to assert ownership, rather than the user or agent key signing everything. <!--  -->, superseded — see nostr-remote-signer.)

Per-podcast NIP-F4 events are signed with per-podcast secp256k1 keys registered as non-active NMP accounts via nmp_app_create_new_account(make_active: false), not stored in the Keychain via PodcastKeyStore keyed by podcast UUID. (Previously: Per-podcast private keys are stored in the Keychain via PodcastKeyStore, keyed by podcast UUID, superseded — see nip74-episode-events.) Per-podcast keys are registered as non-active NMP accounts via nmp_app_create_new_account(make_active: false) rather than stored in the Keychain, so deleting a podcast no longer requires Keychain cleanup of a per-podcast private key. (Previously: Deleting a podcast cleans up its per-podcast private key from the Keychain. <!--  -->, superseded — see nip74-episode-events.)

## Relay Connections

The app connects to Nostr relays once and lets NMP drive all relay routing automatically; the app must not specify relay URLs at publish or subscribe time. (Previously: The app connects to both `wss://relay.primal.net` and the user-configured relay (default `wss://relay.tenex.chat`), not just one or the other. <!--  -->, superseded — see nostr-rust-ffi.)

NIP-F4 podcast discovery works regardless of whether the agent's Nostr features are enabled; the app always connects to discovery relays for podcast browsing, and `nostrEnabled` only gates agent-specific Nostr features like publishing and DMs. <!-- [^144a7-8] -->

The app connects to Nostr relays once and lets NMP drive all relay routing automatically; the app must not specify relay URLs at publish or subscribe time, so the discovery form does not manage relay URLs or show a 'Nostr not configured' state. (Previously: The discovery form always has a valid relay URL (falling back to `wss://relay.primal.net` if no user relay is configured) and never shows a 'Nostr not configured' state for podcast browsing. <!--  -->, superseded — see nostr-rust-ffi.)

## Out-of-Scope Residue

Per-podcast NIP-F4 events are signed with per-podcast secp256k1 keys registered as non-active NMP accounts via nmp_app_create_new_account(make_active: false); the app does not sign these directly, replacing the deferred app-Rust signing approach. (Previously: App-Rust signing in `host_op_publish.rs` and `blossom.rs` for per-podcast NIP-F4 and Blossom kind:24242 is a known out-of-scope residue, deferred to a follow-up (PR #246). <!--  -->, superseded — see nip74-episode-events.)


The Blossom audio-path migration (host_op_publish::publish_episode → nmp.blossom.upload) is blocked upstream because signer_pubkey selects from the kernel's registered signer roster and there is no API to register per-podcast NIP-F4 keys from PodcastKeyStore into that roster. <!-- [^c1691-184] -->
## Testing

Manager-level tests must be added only after injecting publisher, blossom, and key-store dependencies; the current manager hard-codes network/keychain paths. <!-- [^rollo-184] -->

New tests for `NostrPodcastPublisher` must assert kinds `10154`, `54`, `10064`, no `d`/`a` tags, show `description` tag, episode `audio` tag, and podcast-key signer vs agent-key claim signer. No WebSocket awareness (URLSessionWebSocketTask, direct relay connections) belongs in Swift; all Nostr relay communication is NMP's responsibility, so NostrPodcastDiscoveryService no longer has hardcoded WebSocket collection or private parsers requiring a test seam around collectEvents. (Previously: New tests for `NostrPodcastDiscoveryService` require a test seam around `collectEvents` due to hardcoded WebSocket collection and private parsers. <!--  -->, superseded — see nostr-rust-ffi.)
