---
type: episode-card
date: 2026-05-13
session: 9f2d26f1-3e71-46b0-83d8-cc9895be3a8e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9f2d26f1-3e71-46b0-83d8-cc9895be3a8e.jsonl
salience: root-cause
status: superseded
subjects:
  - nip-90-transcription
  - nostr-relay-constraints
  - blossom-upload
supersedes: []
related_claims: []
source_lines:
  - 63-63
captured_at: 2026-06-12T12:09:31Z
---

# Episode: Transcript Payload Size Exceeds Relay Limits — Blossom Upload Required

## Prior State

Naive assumption that transcript text could be published directly in NIP-90 Nostr events.

## Trigger

Typical 60-min transcript is 100–500 KB, 2-hour is ~1 MB. Most public relays reject events >64–256 KB.

## Decision

Inline publishing is only viable for short episodes. For most content, transcript JSON must be uploaded to Blossom and a URL+sha256 placed in the Nostr event. BlossomUploader exists but is only wired for profile photos today.

## Consequences

- Blossom-URL-in-Nostr-event wiring is net-new work
- Short episodes could still inline, but the default path must be Blossom-first
- Adds a dependency on Blossom availability for transcript publishing reliability

## Open Tail

- Final decision needed: always-Blossom vs conditional (inline for short, Blossom for long)

## Evidence

- transcript lines 63-63

