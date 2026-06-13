---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: active
subjects:
  - blossom-upload
  - action-results-bridge
  - swift-transport-deletion
supersedes:
  - 2026-06-12-1-blossom-upload-bespoke-swift-transport-replaced
related_claims: []
source_lines:
  - 6098-6108
  - 6241-6266
  - 6401-6453
  - 6545-6567
captured_at: 2026-06-12T22:54:33Z
---

# Episode: Blossom upload: Swift HTTP transport → kernel nmp.blossom.upload action

## Prior State

BlossomUploader.swift + KernelSigner handled HTTP upload and Nostr signing directly in Swift — a D13/D0 violation where the app side owned transport and crypto.

## Trigger

NMP v0.6.0 shipped nmp-blossom with a typed nmp.blossom.upload action (sign+transport for both nsec and NIP-46 bunker), making the Swift transport entirely replaceable.

## Decision

Route avatar and artwork uploads through the kernel's nmp.blossom.upload action. Add ActionResultsRegistry (drain-once async bridge mirroring SignedEventsRegistry) + decode_action_results_sidecar FlatBuffer bridge. Delete BlossomUploader.swift and BlossomUploaderTests.swift. Defer KernelSigner removal (dead code but cascades into NostrSigner protocol).

## Consequences

- Last Swift upload transport deleted — D13/D0 clean (no signing, no URLSession/HTTP in the Swift path)
- ActionResultsRegistry provides the async-result bridge pattern (dispatchSilent → 60s race → parse BlobDescriptor url)
- Multi-server upload shape (nested servers array, no top-level url) is a latent risk: future callers passing >1 server hit malformedDescriptor — single-server callers are safe
- kernelsigner-deadcode-removal tracked in BACKLOG
- Audio-path Blossom migration deferred: per-podcast NIP-F4 keys live in PodcastKeyStore, not the NMP roster that signer_pubkey resolves against

## Open Tail

- blossom-audio-path-migration — per-podcast signing key resolution differs from account-level signer_pubkey
- Future multi-server callers need a shape-aware decoder for the nested BlobDescriptor

## Evidence

- transcript lines 6098-6108
- transcript lines 6241-6266
- transcript lines 6401-6453
- transcript lines 6545-6567

