---
type: episode-card
date: 2026-05-15
session: a42285c2-863e-42d1-a433-e7bf25bcfc21
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a42285c2-863e-42d1-a433-e7bf25bcfc21.jsonl
salience: architecture
status: active
subjects:
  - apptheme-colors
  - wiki-confidence-colors
  - threading-colors
  - voice-state-colors
supersedes: []
related_claims: []
source_lines:
  - 1349-1355
  - 1575-1598
  - 1743-1755
captured_at: 2026-06-12T12:35:06Z
---

# Episode: Hardcoded RGB colors centralized into AppTheme tokens

## Prior State

Wiki, Threading, and Voice views contained scattered hardcoded RGB color literals for confidence grades, contradiction indicators, and voice orb states — e.g., Color(red: 0.18, green: 0.55, blue: 0.34) for high evidence, Color(red: 0.62, green: 0.45, blue: 1.0) for thinking state. No design tokens existed for these semantic meanings.

## Trigger

Consistency audit found magic-number colors in EvidenceGradedRule, CitationPeekView, WikiGenerateSheet, WikiView, WikiPageView, ThreadingMentionRow, ThreadingTopicListView, VoiceView, and VoiceOrbView.

## Decision

Added six new semantic tokens to AppTheme.Tint: evidenceHigh/Medium/Low, threadingContradiction, voiceListening/Thinking/Speaking. Replaced all hardcoded RGB values with token references.

## Consequences

- Single source of truth for evidence-grade colors, threading contradiction color, and voice-state colors
- Future theme adjustments propagate from AppTheme+Colors.swift rather than requiring hunts across feature files
- WikiPageView error color replaced with AppTheme.Tint.error (was also hardcoded RGB)

## Open Tail

- voiceSpeaking token added but VoiceView 'speaking' state uses a different green (0.36, 0.85, 0.78) — may need a dedicated token or consolidation with the existing elevenLabsTint

## Evidence

- transcript lines 1349-1355
- transcript lines 1575-1598
- transcript lines 1743-1755

