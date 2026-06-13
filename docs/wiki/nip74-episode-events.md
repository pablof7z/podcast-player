---
title: NIP-74 Episode Events
slug: nip74-episode-events
topic: nostr-protocol
summary: NIP-F4 episode events do not emit `d`, `a`, or `published_at` tags
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-26
updated: 2026-06-12
verified: 2026-05-26
compiled-from: conversation
sources:
  - session:378a594b-f095-461d-a035-4d3afca30d5e
  - session:c43d5e77-d667-4e71-a574-47aaab5b6a7a
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
  - session:rollout-2026-05-25T12-53-39-019e5e8d-ec64-74f1-a1b1-91055dcab442
  - session:rollout-2026-05-26T09-10-44-019e62e8-3112-7080-98ca-48ac46d8b8d2
  - session:rollout-2026-05-26T10-15-57-019e6323-e656-7e70-b925-0b0c837b24a1
  - session:rollout-2026-05-26T10-16-01-019e6323-f6b1-7f03-85ec-1a51289f331a
  - session:rollout-2026-05-26T10-16-06-019e6324-08b0-7ca3-9b29-a0e8cf84941d
  - session:rollout-2026-05-26T10-16-10-019e6324-1915-7ba0-91ff-8397304bb76a
---

# NIP-74 Episode Events

## Episode Event Structure

NIP-F4 correctness is the next P0: stale NIP-74 tag shapes must be removed, per-podcast keys must be persisted with real secp256k1 pubkeys, events must be signed and published to relays, and protocol tests must be added. The NIP-F4 builder must not emit `d`, `a`, `published_at`, `summary`, or `imeta` tags; instead it must use `description` and `audio` tags as specified in the migration contract. Audio is specified using an `audio` tag formatted as `["audio", url, mime]`. The `Imetadata` struct is simplified to contain only `mime_type: Option<String>`, as the sole field still relevant to the `audio` tag. The `episode_to_episode_tags` signature no longer takes `show_pubkey` or `show_d` parameters. The `lib.rs` doc comment describes episode events without mentioning d-tag replaceability. Per-podcast NIP-F4 events (kind:10154/54) are signed with per-podcast secp256k1 keys registered as non-active NMP accounts via `nmp_app_create_new_account(make_active: false)`; the app does not sign these directly. Publishing must actually sign and broadcast events to relays, not return `relay_pending` without signing or broadcasting. Nostr kind:54 episode fetch uses a lazy OnceLock-registered observer that opens relay interest after registration, so no events are dropped during the EOSE sweep, and feedless shows use UUIDv5-derived stable IDs. Discovery must use kinds 10154/54, remove dTag, look up episodes by `authors:[show.pubkey]`, dedupe by event id, and parse `audio`, `description`, and `created_at`. NostrPodcastPublisherTests must cover show kind/tags, episode kind/tags, absence of removed tags, and author claim. Discovery parser/filter tests must be added; current parsing is private/network-bound, so a small parser/filter helper must be extracted or internals made testable.

After NIP-F4 correctness is verified, focused Rust tests for podcast-discovery and nmp-app-podcast must be run, followed by full `cargo test --workspace`, `git diff --check`, and the iOS build/test gate. Compat stubs and AI/platform scaffolds must then be burned down one by one, with done meaning user-visible behavior works, not just that a view compiles. New feature fan-out must stop until NIP-F4 correctness, compat stub burn-down, and AI/platform scaffold replacement are addressed. The next correct work after the cleanup sweep is: NIP-F4 persisted keys/signing/relay publish/discovery/author claims, broaden iOS validation, then compat shim burn-down and Tier 1 device validation.

<!-- citations: [^rollo-181] [^rollo-224] [^378a5-1] [^c43d5-3] [^c1691-27] [^rollo-180] [^rollo-223] [^rollo-235] [^rollo-241] [^rollo-248] [^rollo-253] -->
