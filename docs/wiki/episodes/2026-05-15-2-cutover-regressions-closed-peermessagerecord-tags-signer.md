---
type: episode-card
date: 2026-05-15
session: f3b466c6-7791-44b3-b004-aae2066a9019
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/f3b466c6-7791-44b3-b004-aae2066a9019.jsonl
salience: product
status: active
subjects:
  - peer-message-record
  - signer-bootstrap
  - app-observers
  - republish-agent-profile
supersedes: []
related_claims: []
source_lines:
  - 2281-2288
  - 2383-2390
  - 2466-2483
  - 2537-2591
  - 2593-2627
captured_at: 2026-06-12T12:39:29Z
---

# Episode: Cutover regressions closed: PeerMessageRecord tags, signer bootstrap, observer wiring

## Prior State

After the Rust migration, several functional regressions existed: PeerMessageRecord lacked tags/raw JSON (breaking NIP-10 root resolution and delegation routing), republishAgentProfile had no extra_tags (legacy `backend` identification tag was dropped), the Rust signer was never loaded from Keychain at boot (all signed operations silently failed), and Nostr app observers were never called from AppStateStore.init (signer/relay deltas never reached UI state).

## Trigger

Explicit identification of 6 FIXMEs during migration review, followed by user directive to improve the PR.

## Decision

Extended PeerMessageRecord with `tags: Vec<Vec<String>>` and `raw_json: Option<String>`. Added `extra_tags` parameter to `republishAgentProfile`. Called `bootstrapNostrSession` from AppStateStore.init to load Keychain private key into Rust core. Called `installNostrAppObservers()` from AppStateStore.init. Replaced 3× deprecated `Timestamp::as_u64` with `as_secs`.

## Consequences

- NIP-10 root/reply tag resolution and delegation routing now work through the Rust core
- Agent profile republishing carries the `backend` identification tag again
- Signed Nostr operations (publishing, NIP-46) function at runtime instead of silently failing
- Signer status and relay diagnostics deltas now propagate to AppState/UI

## Open Tail

- PodcastEpisodeRecord still missing publishedAt, imageUrl, transcript MIME type

## Evidence

- transcript lines 2281-2288
- transcript lines 2383-2390
- transcript lines 2466-2483
- transcript lines 2537-2591
- transcript lines 2593-2627

