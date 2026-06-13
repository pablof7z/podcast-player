---
type: episode-card
date: 2026-05-13
session: 31314bf9-84f5-4c58-b2e7-b4d8aed0bf26
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/31314bf9-84f5-4c58-b2e7-b4d8aed0bf26.jsonl
salience: reversal
status: superseded
subjects:
  - photo-upload
  - blossom-bud-02
  - change-photo-sheet
  - identity-profile
supersedes: []
related_claims: []
source_lines:
  - 1-1
  - 26-51
  - 310-312
  - 330-330
  - 400-404
  - 490-497
  - 596-618
captured_at: 2026-06-12T12:02:07Z
---

# Episode: Photo upload via Blossom: deferred feature ships now

## Prior State

ChangePhotoSheet had disabled 'Choose from library' and 'Take photo' rows with footer copy stating they require a media host. The identity briefs explicitly declared 'No camera. No photo picker. No upload pipeline.' and labeled photo upload as a future/separate brief (identity-04-blossom).

## Trigger

User directive overriding the deferral: "'Photo upload arrives with a future update'… do it now."

## Decision

Implemented photo upload using Blossom BUD-02 protocol. Created BlossomUploader service (SHA-256 hash → sign kind:24242 auth event via existing NostrSigner → PUT /upload to blossom.band). Wired a live PhotosPicker into ChangePhotoSheet, replacing the disabled library row. Removed disabled 'Take photo' row entirely. Images are resized to 800×800 JPEG at q=0.85 before upload.

## Consequences

- Users can now set a profile photo by picking from their photo library — the feature is live instead of deferred
- Single Blossom host (blossom.band) with no fallback; architecture comment states: swap defaultServer if it goes down
- Camera capture still not implemented (separate brief, per advisor's recommendation)
- No 'remove photo' affordance, no local caching of uploaded photos, no multi-host fallback yet
- Kind:24242 auth event ties upload authorization to the user's existing Nostr identity/signer

## Open Tail

- Camera capture remains unimplemented (was removed as a disabled row, not replaced)
- No remove-photo affordance yet
- No local cache of uploaded photos
- No multi-host fallback list

## Evidence

- transcript lines 1-1
- transcript lines 26-51
- transcript lines 310-312
- transcript lines 330-330
- transcript lines 400-404
- transcript lines 490-497
- transcript lines 596-618

