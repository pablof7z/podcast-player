---
type: episode-card
date: 2026-06-04
session: 56e47844-b4ff-4402-9528-c704eade1d7b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/56e47844-b4ff-4402-9528-c704eade1d7b.jsonl
salience: product
status: active
subjects:
  - agent-llm-fallback
  - error-messaging
  - agent-ux
supersedes: []
related_claims: []
source_lines:
  - 4806-4806
  - 5132-5138
captured_at: 2026-06-12T13:17:31Z
---

# Episode: Ad-hoc agent fallback removed — local model errors now surface directly

## Prior State

When local model inference failed (e.g. mmap ENOMEM), the agent_llm code fell back to an alternate path that produced a generic 'Couldn't reach the agent' error, masking the real failure cause.

## Trigger

User directive to remove the fallback; the misleading generic error obscured the real mmap failure, making diagnosis much harder

## Decision

Removed the ad-hoc fallback in agent_llm.rs so that a failed local model now surfaces its actual error (e.g. 'LLM unavailable: Invalid response from native layer: Native sendMessage returned null')

## Consequences

- Real local-model errors are now visible to users instead of being hidden behind a misleading connectivity message
- Future failures are diagnosable from the error text alone
- No silent degradation path — agent either works or shows the real error

## Open Tail

*(none)*

## Evidence

- transcript lines 4806-4806
- transcript lines 5132-5138

