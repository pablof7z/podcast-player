---
type: episode-card
date: 2026-05-15
session: 8c3708b9-22f2-404d-8534-c476e0cfcf75
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8c3708b9-22f2-404d-8534-c476e0cfcf75.jsonl
salience: architecture
status: superseded
subjects:
  - ndkswift-migration
  - nostr-networking
  - relay-pool
supersedes: []
related_claims: []
source_lines:
  - 1-3767
captured_at: 2026-06-12T12:37:22Z
---

# Episode: NDKSwift replaces custom Nostr WebSocket layer

## Prior State

All Nostr networking used hand-rolled URLSessionWebSocketTask connections: manual REQ/EOSE/CLOSE JSON framing, per-call WebSocket opens, raw NIP-46 crypto (ChaCha20, Nip44), a custom RemoteSigner, and ad-hoc publish fan-out to relay URL lists.

## Trigger

User directive to adopt https://github.com/pablof7z/NDKSwift as the Nostr networking library, replacing ~4000 lines of custom WebSocket code across 108 files.

## Decision

Migrated all Nostr services to NDKSwift: signing via NDKPrivateKeySigner/NDKBunkerSigner, read-path via ndk.subscribe with AsyncStream, write-path via ndk.publish, relay management via NDK's shared relay pool with NIP-65 outbox routing. Deleted Nip46/* (ChaCha20, Nip44, RemoteSigner, BunkerURI, NostrSigner), NostrKeyPair, and the custom WebSocket framing. Introduced NostrStack as the shared NDK owner and NDKEventConverter as single source of truth for SignedNostrEvent → NDKEvent conversion.

## Consequences

- No more URLSessionWebSocketTask in any Nostr service — all relay I/O goes through NDK's pooled connections
- NostrStack.shared.ndk is the single relay-pool owner; services gate on NostrStack.shared.relaysConnected
- NIP-46 bunker users must re-pair their signer (old Keychain sessions purged)
- Public API signatures preserved (relayURL params kept as vestigial for compatibility)
- Deleted Nip46Tests.swift and Nip46RemoteSignerTests.swift — tested code that no longer exists
- Vestigial init params remain on NostrPodcastPublisher (publisher, relayURLs) and read-path services (relayURL:) for API stability

## Open Tail

- Pin NDKSwift to a tagged release rather than branch("master") before shipping
- Drop vestigial init params (publisher, relayURLs, relayURL) once callers are refactored
- Consider promoting NDKEvent/NDKFilter types directly into callers and deprecating the SignedNostrEvent/NostrEventDraft shim layer

## Evidence

- transcript lines 1-3767

