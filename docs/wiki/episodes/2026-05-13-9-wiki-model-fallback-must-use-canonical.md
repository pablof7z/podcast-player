---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: architecture
status: superseded
subjects:
  - wiki-model
  - settings-defaults
  - source-of-truth
supersedes: []
related_claims: []
source_lines:
  - 487-504
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Wiki model fallback must use canonical defaults, not hardcoded literals

## Prior State

LiveWikiStorageAdapter fell back to the hardcoded string "openai/gpt-4o-mini" when Settings.wikiModel was nil, duplicating the value that already lived in Settings.Defaults.llmModel.

## Trigger

Audit found the inlined literal; the canonical default existed but wasn't being referenced.

## Decision

Replaced ?? "openai/gpt-4o-mini" with ?? Settings() and read .wikiModel off that, so the canonical default lives in exactly one place (Settings.Defaults private enum).

## Consequences

- Changing the default model in Settings.Defaults now automatically flows to the wiki adapter
- Eliminates a class of drift bugs where the fallback literal diverges from the canonical default

## Open Tail

- BriefingComposer.swift and WikiOpenRouterClient.swift still have hardcoded "openai/gpt-4o-mini" in default parameter values — separate domain, not changed

## Evidence

- transcript lines 487-504

