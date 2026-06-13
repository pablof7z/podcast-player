---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: product
status: active
subjects:
  - podcast-identity
  - placeholder-titles
  - hydration-failure
supersedes: []
related_claims: []
source_lines:
  - 836-879
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Placeholder podcast titles must be trackable and clearable

## Prior State

When a podcast feed failed to hydrate, the hostname (e.g. 'feeds.example.com') was used as the title and persisted permanently — no way to distinguish it from a real title or retry hydration.

## Trigger

Audit found that resolveExternalParent, hydratePlaceholderPodcastMetadata, ensurePodcast, and addSubscription all constructed placeholders with no flag; hydration failure was logged at .notice (invisible).

## Decision

Added titleIsPlaceholder: Bool to Podcast model (decodeIfPresent ?? false for migration). Set true at all four placeholder-construction sites; cleared only after successful feed fetch. Hydration failure now logged at .error.

## Consequences

- UI can now differentiate real titles from placeholder fallbacks
- Hydration failures are visible in Console.app for debugging
- Codable backward-compatible: old JSON missing the key decodes as false

## Open Tail

- UI doesn't yet render placeholder titles differently — the flag is set but no visual distinction exists

## Evidence

- transcript lines 836-879

