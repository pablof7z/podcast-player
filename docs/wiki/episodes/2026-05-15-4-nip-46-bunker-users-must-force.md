---
type: episode-card
date: 2026-05-15
session: 8c3708b9-22f2-404d-8534-c476e0cfcf75
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8c3708b9-22f2-404d-8534-c476e0cfcf75.jsonl
salience: product
status: active
subjects:
  - nip-46
  - bunker-signer
  - force-repair
supersedes: []
related_claims: []
source_lines:
  - 3525-3567
captured_at: 2026-06-12T12:37:22Z
---

# Episode: NIP-46 bunker users must force re-pair after migration

## Prior State

NIP-46 session state (nip46-session, nip46-meta) was stored in Keychain by the custom RemoteSigner implementation. Bunker URIs and session secrets were tied to that code.

## Trigger

Migration deleted the entire custom NIP-46 implementation (BunkerURI, RemoteSigner, Nip46Message, ChaCha20, Nip44) and replaced it with NDKSwift's NDKBunkerSigner. Old Keychain entries are incompatible with the new signer.

## Decision

Purge legacy Keychain entries (nip46-session, nip46-meta) on next launch and force a fresh bunker re-pair. Added whats-new entry: 'NIP-46 bunker users: re-pair your signer after this update.'

## Consequences

- Users with existing NIP-46 bunker pairings will lose their active session and must re-pair
- The whats-new entry surfaces this to the user
- No backward-compatible migration path for old session tokens — they are cryptographically tied to the old implementation

## Open Tail

- Runtime test needed: force re-pair against a device with real legacy nip46-session/nip46-meta Keychain entries
- Verify the purge logic runs before any signer access attempt

## Evidence

- transcript lines 3525-3567

