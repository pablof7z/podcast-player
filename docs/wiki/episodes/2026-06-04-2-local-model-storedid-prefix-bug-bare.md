---
type: episode-card
date: 2026-06-04
session: 2ad3bd09-6020-4da7-a0d2-39e7e5434cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/2ad3bd09-6020-4da7-a0d2-39e7e5434cfa.jsonl
salience: root-cause
status: active
subjects:
  - local-model-stored-id
  - llm-routing
supersedes:
  - 2026-06-04-1-local-models-restructured-from-global-override
related_claims: []
source_lines:
  - 681-698
captured_at: 2026-06-12T13:15:56Z
---

# Episode: Local model storedID prefix bug: bare IDs mis-parsed as OpenRouter

## Prior State

LLMModelReference.storedID for .local provider emitted the bare modelID (e.g. 'gemma4-e2b') without a provider prefix, while .ollama correctly emitted 'ollama:<id>'. A bare ID with no colon would fall through to OpenRouter routing in the kernel's backend_for, silently misrouting local model requests to OpenRouter.

## Trigger

Discovery during the per-role restructuring: the storedID switch-case for .local returned raw modelID with no prefix, creating a latent routing bug where any local model storedID would be parsed as an OpenRouter model.

## Decision

Changed .local case to emit 'local:<id>' format, matching the ollama: prefix pattern. Rust backend_for now checks for 'local:' prefix to route per-role local requests.

## Consequences

- Existing persisted settings with bare local model IDs (no prefix) will need migration or will be mis-parsed.
- The per-role routing in Rust now correctly dispatches local-prefixed models to LocalModelBackend.

## Open Tail

- Migration path for any persisted bare local model IDs in user settings.

## Evidence

- transcript lines 681-698

