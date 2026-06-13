---
type: episode-card
date: 2026-05-15
session: a42285c2-863e-42d1-a433-e7bf25bcfc21
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a42285c2-863e-42d1-a433-e7bf25bcfc21.jsonl
salience: product
status: active
subjects:
  - artwork-placeholder
  - episode-row
  - home-resume-card
  - home-agent-pick-card
  - player-view
  - bookmarks-view
supersedes: []
related_claims: []
source_lines:
  - 1232-1238
  - 1269-1275
  - 1660-1680
captured_at: 2026-06-12T12:35:06Z
---

# Episode: Artwork placeholder unified to single neutral treatment

## Prior State

Four distinct artwork placeholder styles existed: EpisodeRow used accent-color gradient + waveform; BookmarkRow used Color(.secondarySystemBackground) + waveform; HomeResumeCard used Color(.tertiarySystemFill) + waveform; PlayerView/MiniPlayerView used Color.secondary.opacity(0.18) + waveform. EpisodeDetailHeroView used a distinctive orange/purple gradient with first-letter overlay.

## Trigger

Consistency survey identified the fragmentation — each surface independently chose a different placeholder style, producing visual inconsistency when the user scrolls through episodes across contexts.

## Decision

Standardized all artwork placeholders to Color.secondary.opacity(0.18) + waveform icon, matching the existing AppTheme.Tint.hairline token. The orange/purple gradient in EpisodeDetailHeroView was replaced.

## Consequences

- Single visual language for missing artwork across the entire app
- EpisodeDetailHeroView loses its distinctive warm gradient — now matches the neutral treatment
- Future placeholder changes propagate from one pattern

## Open Tail

*(none)*

## Evidence

- transcript lines 1232-1238
- transcript lines 1269-1275
- transcript lines 1660-1680

