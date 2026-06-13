---
type: episode-card
date: 2026-05-14
session: 84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d.jsonl
salience: product
status: active
subjects:
  - agent-owned-podcast
  - nostr-visibility
  - settings-toggle
supersedes: []
related_claims: []
source_lines:
  - 3616-3633
  - 4014-4016
captured_at: 2026-06-12T12:27:32Z
---

# Episode: Visibility toggle now publishes to Nostr

## Prior State

The public/private toggle in AgentPodcastsView only called store.updatePodcast(updated), mutating local state but never triggering NIP-74 event publishing — so a podcast marked 'public' would not appear on Nostr relays

## Trigger

Codex review found the toggle bypasses the manager's updatePodcast which handles Nostr publishing

## Decision

Route the toggle's set handler through LiveAgentOwnedPodcastManager.updatePodcast in an async Task, which triggers publishShowEvent when going public

## Consequences

- Toggling a podcast to public now actually publishes the NIP-74 show event to relays
- Local state mutation still happens immediately via store.updatePodcast for responsive UI, with Nostr publish as a fire-and-forget side effect

## Open Tail

*(none)*

## Evidence

- transcript lines 3616-3633
- transcript lines 4014-4016

