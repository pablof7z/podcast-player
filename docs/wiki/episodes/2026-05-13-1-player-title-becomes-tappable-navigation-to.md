---
type: episode-card
date: 2026-05-13
session: 82bb4074-1526-4549-8697-19bfe9a117be
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/82bb4074-1526-4549-8697-19bfe9a117be.jsonl
salience: product
status: active
subjects:
  - player-title-navigation
  - episode-detail-link
supersedes: []
related_claims: []
source_lines:
  - 1-1
  - 158-158
  - 181-181
  - 205-205
  - 236-236
  - 281-307
captured_at: 2026-06-12T12:13:00Z
---

# Episode: Player title becomes tappable navigation to episode detail

## Prior State

The episode title in PlayerView was static, non-interactive text. Users could only reach the episode detail page through the 'More' menu's 'Go to episode' option.

## Trigger

User explicitly requested that tapping the title on the player should navigate to the episode's page.

## Decision

Wrap the title Text in a Button that calls a new openEpisodeDetail(_:) helper, posting the same .openEpisodeDetailRequested notification already used by PlayerMoreMenu's 'Go to episode' item — reusing the race-free notification path rather than a URL-based approach.

## Consequences

- Users can now tap the episode title in the full-screen player to navigate directly to the episode detail page.
- Navigation reuses the atomic notification path, avoiding the sheet-dismissal animation race that previously crashed SwiftUI when presenting over a dismissing sheet.
- The whats-new changelog reflects the feature.

## Open Tail

*(none)*

## Evidence

- transcript lines 1-1
- transcript lines 158-158
- transcript lines 181-181
- transcript lines 205-205
- transcript lines 236-236
- transcript lines 281-307

