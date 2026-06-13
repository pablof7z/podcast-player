---
type: episode-card
date: 2026-05-13
session: 9692d124-a1a0-411c-91f9-9d6ebc0b29b1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9692d124-a1a0-411c-91f9-9d6ebc0b29b1.jsonl
salience: reversal
status: active
subjects:
  - settings-ui
  - cta-placement
  - ios-conventions
supersedes: []
related_claims: []
source_lines:
  - 1523-2059
captured_at: 2026-06-12T12:21:42Z
---

# Episode: Settings Save CTAs moved from inline form rows to navigation bar trailing

## Prior State

All settings screens (YouTube, Ollama, AssemblyAI, OpenRouter, ElevenLabs, Perplexity) had 'Save ...' buttons embedded as inline Button rows inside Form/Section bodies — non-standard iOS placement

## Trigger

User explicitly corrected: 'default CTAs on an iPhone shouldn't be located there; they should be a top right button on the sheet — review all of them'

## Decision

Replaced all inline 'Save Endpoint'/'Save Manual Key' buttons with `.toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { ... } } }` across all 6 settings screens. Text fields also gained `onSubmit` to commit on keyboard return. Destructive actions (Disconnect, Remove Endpoint, Reset to Default) remain inline as is conventional.

## Consequences

- Establishes a reusable pattern: primary CTAs in nav bar trailing, destructive actions inline
- Six files changed: YouTubeSettingsView, OllamaSettingsView, AssemblyAISettingsView, OpenRouterSettingsView, ElevenLabsSettingsView (+ ElevenLabsConnectionSection), AISettingsView (PerplexitySettingsView)
- ElevenLabsConnectionSection had its `onSaveManualKey` callback removed; the parent now owns the toolbar button

## Open Tail

*(none)*

## Evidence

- transcript lines 1523-2059

