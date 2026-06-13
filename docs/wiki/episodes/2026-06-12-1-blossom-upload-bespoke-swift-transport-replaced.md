---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - blossom-upload
  - swift-transport-deletion
  - action-results-ffi
supersedes:
  - 2026-06-12-4-nmp-v0-6-0-dissolves-blossom
related_claims: []
source_lines:
  - 6070-6077
  - 6241-6282
  - 6401-6453
  - 6545-6568
  - 6582-6594
captured_at: 2026-06-12T22:28:01Z
---

# Episode: Blossom upload: bespoke Swift transport replaced by kernel nmp.blossom.upload action

## Prior State

Avatar and artwork uploads used a bespoke BlossomUploader.swift with direct HTTP transport and KernelSigner for signing — the last Swift-side upload transport and one of two remaining app-Rust direct-nostr signing sites (D13 violation)

## Trigger

NMP v0.6.0 (#414) shipped nmp_blossom with nmp.blossom.upload — a typed kernel action owning the full Build→Sign→Transport pipeline, supporting both local nsec and NIP-46 bunker transparently via SignEventForAccount

## Decision

Adopt the upstream kernel action for all Blossom uploads; delete BlossomUploader.swift entirely; add an action_results FlatBuffer decode bridge (ActionResultsRegistry in Swift mirroring SignedEventsRegistry) so the shell can await async results; route avatar (ChangePhotoSheet) and artwork (LiveAgentOwnedPodcastManager) through the kernel dispatch

## Consequences

- D13/D0 compliance: zero signing or URLSession/HTTP remains in Swift for uploads
- BlossomUploader.swift + BlossomUploaderTests.swift deleted (orphaned test caught by Opus review — the same build-for-testing trap as #413)
- KernelSigner is now dead code (deferred removal to avoid touching unrelated NostrSignerError consumers)
- Audio-path Blossom migration deferred: per-podcast NIP-F4 keys live in PodcastKeyStore, not the NMP account roster that signer_pubkey resolves against
- Future multi-server callers would hit a shape mismatch (no top-level url) — documented as a latent risk in blossomUpload
- Round-trip FFI decode test added (embedded KARS FlatBuffer fixture → decode_action_results_sidecar → BlobDescriptor url)

## Open Tail

- kernelsigner-deadcode-removal tracked in BACKLOG
- blossom-audio-path-migration tracked in BACKLOG (needs per-podcast NIP-F4 key resolution)
- Future multi-server Blossom callers need nested-shape handling in Swift decode

## Evidence

- transcript lines 6070-6077
- transcript lines 6241-6282
- transcript lines 6401-6453
- transcript lines 6545-6568
- transcript lines 6582-6594

