---
type: episode-card
date: 2026-05-14
session: 84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d.jsonl
salience: root-cause
status: active
subjects:
  - agent-owned-podcast
  - nostr-visibility
  - create-podcast
supersedes: []
related_claims: []
source_lines:
  - 3596-3612
  - 4010-4012
captured_at: 2026-06-12T12:27:32Z
---

# Episode: Private show creation no longer requires Nostr key

## Prior State

createPodcast unconditionally called agentPubkeyHex(), which throws when no Nostr key is configured — this blocked private show creation even though private shows never need a real pubkey

## Trigger

Codex review identified that private show creation fails without a Nostr key configured

## Decision

Conditionally require the key: public visibility still throws, but private visibility falls back to sentinel string 'agent-private' when no key is present

## Consequences

- Private shows can be created without configuring Nostr credentials
- ownerPubkeyHex sentinel 'agent-private' is safe because the field is only ever checked for nil/non-nil, never hex-decoded

## Open Tail

*(none)*

## Evidence

- transcript lines 3596-3612
- transcript lines 4010-4012

