---
type: episode-card
date: 2026-06-04
session: 2ad3bd09-6020-4da7-a0d2-39e7e5434cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/2ad3bd09-6020-4da7-a0d2-39e7e5434cfa.jsonl
salience: reversal
status: superseded
subjects:
  - local-model-provider
  - llm-routing
  - model-selector
  - per-role-models
supersedes:
  - 2026-06-03-2-local-on-device-model-added-as
related_claims: []
source_lines:
  - 1-6
  - 536-541
  - 681-698
  - 926-950
  - 1025-1050
  - 1067-1093
  - 1379-1399
captured_at: 2026-06-12T13:15:56Z
---

# Episode: Local models restructured from global override to per-role provider

## Prior State

Local models were a global switch: setting an active local model dominated ALL LLM calls across every role (agent, thinking, memory, wiki, etc.). The Models screen had a separate 'On-Device' section unrelated to the per-role selectors. In Rust, backend_for checked store.local_model_id first and forced LocalModelBackend for every caller regardless of their role's chosen model.

## Trigger

User directive: 'The way the gemma models is structured doesn't make sense. Settings > Providers > Local for downloading, then Settings > Models > {each role} where Local is just another available provider like Ollama, OpenRouter.'

## Decision

Local is now a per-role provider. Each role (agent initial, thinking, memory, wiki, categorization, chapter, embeddings) independently selects a model from any provider including Local. The global 'On-Device' section was removed from the Models screen; 'Local' row added to the Providers screen for download management only. Rust backend_for routes on the 'local:' stored-ID prefix per-role instead of checking a global local_model_id override. local_model_id is retained only as the single-engine-to-load signal, derived from whichever roles point at a local model (Agent-Initial precedence). The onActivate global-toggle was removed from LocalModelRowView; kernelSetLocalModel was deleted as dead code.

## Consequences

- Each AI role can independently select a local model or a cloud model — no more forced all-or-nothing local routing.
- Only one on-device engine can be loaded at a time; effectiveLocalModelID() derives which one from role assignments with Agent-Initial precedence.
- The LocalLLMService.load(spec:) engine-load seam is still unwired — selecting a local model currently yields 'Local model not loaded' at dispatch (non-regressive; same gap existed before).
- A concurrent peer agent was building overlapping work (local model provider selection + centralized Rust download manager) that was not on origin at merge time — reconciliation may be needed.

## Open Tail

- Local inference end-to-end: LocalLLMService.load(spec:) must be called somewhere to actually load the LiteRT engine before local models produce output.
- Peer agent's unmerged branch may conflict with the new per-role routing on next merge.

## Evidence

- transcript lines 1-6
- transcript lines 536-541
- transcript lines 681-698
- transcript lines 926-950
- transcript lines 1025-1050
- transcript lines 1067-1093
- transcript lines 1379-1399

