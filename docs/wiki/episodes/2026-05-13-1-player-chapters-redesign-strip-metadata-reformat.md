---
type: episode-card
date: 2026-05-13
session: 513924f8-3b98-47b0-a84a-38086416581a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/513924f8-3b98-47b0-a84a-38086416581a.jsonl
salience: product
status: active
subjects:
  - player-chapters
  - chapter-rendering
supersedes: []
related_claims: []
source_lines:
  - 1-57
captured_at: 2026-06-12T12:12:08Z
---

# Episode: Player chapters redesign: strip metadata, reformat active state

## Prior State

Chapters showed an AI label pill, descriptions, timestamps on the left column, and the active chapter had a background highlight plus a speaker icon

## Trigger

User directive to remove AI label, drop descriptions, move timestamps right, and show active chapter only via bold+black vs regular+muted styling

## Decision

Removed aiPill and description blocks entirely; moved timestamp to right column (after Spacer); removed rowBackground; removed playing icon; active chapter = bold + Color.primary, inactive = regular weight + Color.secondary

## Consequences

- Chapter list is visually cleaner and more editorial
- Less metadata surfaced per chapter (no summaries, no AI attribution)
- Active chapter identification relies entirely on typographic weight, not background or icon

## Open Tail

*(none)*

## Evidence

- transcript lines 1-57

