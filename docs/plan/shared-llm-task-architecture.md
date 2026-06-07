# Shared LLM And Task Architecture

This plan captures the architecture contract for provider transport, model
selection, and agent task creation across iOS, Android, and the TUI.

## Contract

Platform shells own:

- Credential capture and secret storage in their platform-native secure store.
- Delivery of live API keys to Rust through the existing in-memory settings
  action (`podcast.settings`, `set_provider_api_keys`).
- Model-selection UI and display labels.
- Rendering, keyboard/touch interaction, local files, audio, downloads, and
  other platform capabilities.

The shared Rust backend owns:

- Provider routing for OpenRouter, Ollama, and local models.
- HTTP request and response shape for provider chat/completions.
- HTTP request and response shape for provider embeddings.
- Provider credential requirements and error messages.
- Role-to-model resolution and validation.
- Agent task intent resolution and dispatch payload construction.

Platform code must not construct OpenRouter or Ollama chat/embedding request
bodies, provider URLs, provider-specific auth headers, or raw backend task
namespace/body JSON for normal user workflows.

## Provider Transport

Current shared Rust provider entry points already cover agent chat through
`nmp_app_podcast_chat_complete`, which hides OpenRouter/Ollama/local routing
from Swift. The remaining work is to make all other provider-backed features
use the same shared transport layer.

Immediate targets:

- Wiki/title/categorization-style single-turn completions need a provider-blind
  Rust FFI that accepts system prompt, user prompt, model role or model id, and
  optional structured-output intent.
- Embeddings need a Rust FFI that accepts texts plus a selected embedding model
  and returns vectors. Both Ollama and OpenRouter embedding HTTP should be
  behind this shared endpoint.
- Swift clients should keep stubbed test modes but route live provider calls
  through Rust.
- Android should expose the same Rust provider functions through JNI once the
  shared FFI exists.

Provider model-list discovery can remain UI-owned temporarily if it is only a
catalog/browser concern, but any provider inference call must use Rust.

## Task Intents

Task creation must submit typed user intent, not raw backend dispatch payloads.
The backend may continue storing an internal dispatch namespace/body for
`run_now` compatibility, but that payload is not a UI contract.

Immediate targets:

- Add a Rust `AgentTaskIntent` enum with variants for currently schedulable
  tasks such as inbox triage, clear agent chat, and memory writes.
- Add a typed task-create action that carries title, schedule, description, and
  intent.
- Resolve `AgentTaskIntent` to the internal action namespace/body inside
  `tasks_handler.rs`.
- Keep raw `create` only as a compatibility/internal action until all platform
  callers migrate.
- Update the TUI task editor to accept concise typed/natural input such as
  `Title | daily | inbox_triage | optional description` instead of namespace
  and JSON body.

## Push Updates

The TUI currently depends on periodic snapshot revision checks for autonomous
backend changes. The long-term shared fix is a backend update signal that fires
when app-owned async work mutates shared projection state and bumps `rev`.

Immediate targets:

- Audit which async host-side paths bump `rev` without triggering the NMP
  update sink.
- Add or expose a shared notification seam if the existing projection registry
  cannot emit after those mutations.
- Keep TUI polling only as a temporary fallback tracked in `docs/BACKLOG.md`.

## PR Sequencing

1. Provider transport PR: move OpenRouter/Ollama inference and embeddings HTTP
   into shared Rust APIs, then migrate Swift live paths to those APIs.
2. Typed task intent PR: add backend intent action and migrate TUI task
   creation away from raw namespace/body JSON.
3. Android/JNI parity PR: expose any new shared provider/task APIs through the
   Android bridge if they are not already reachable.
4. Push-update PR: replace TUI-specific revision polling with shared backend
   update delivery for autonomous state changes.
5. Validation PR: run real TUI/tmux scenarios with `glm-5.1:cloud`, plus focused
   iOS/Android checks for provider settings and model selection.
