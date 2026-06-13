---
type: episode-card
date: 2026-06-10
session: 681fa743-322c-4b1a-8e99-81a97aa1a904
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/681fa743-322c-4b1a-8e99-81a97aa1a904.jsonl
salience: product
status: superseded
subjects:
  - episode-diagnostics
  - transcription-pipeline
  - auto-ingest
supersedes: []
related_claims: []
source_lines:
  - 1-1
  - 2040-2105
  - 2107-2135
captured_at: 2026-06-12T13:42:09Z
---

# Episode: Pipeline diagnostics must explain configuration state upfront

## Prior State

Episode Diagnostics showed only a chronological event log. After a download completed, there was no indication of whether transcription would auto-fire or why it might be silently skipped. The user had to infer pipeline behavior from the absence of events.

## Trigger

User observed: 'after an episode finishes download, I don't see ANY indication that the transcription auto-fires — is that possible?' The silence was not a bug but a deliberate consequence of settings (AI fallback OFF, missing API key, category disabled), but the UI gave no explanation.

## Decision

Added a 'Pipeline configuration' panel at the top of the Diagnostics view that states plainly what will or won't happen — e.g. 'Won't transcribe automatically — AI transcription fallback is OFF' or 'Will transcribe with Apple on-device once downloaded.' It surfaces: AI fallback on/off, selected vs effective STT provider, key configured/missing, category enabled, publisher transcript present, chapter model name, and embeddings model name.

## Consequences

- Users can now diagnose transcription silence without reading event history
- The diagnostic verdict is per-episode (checks publisher transcript URL presence, category setting, key availability) rather than global
- The whats-new.json entry was updated to ship this as a user-facing fix

## Open Tail

- Future: the panel could link directly to the relevant settings screen for one-tap remediation

## Evidence

- transcript lines 1-1
- transcript lines 2040-2105
- transcript lines 2107-2135

