---
type: episode-card
date: 2026-05-12
session: 9d55e84d-b4cf-4c53-80c2-3cbdd80e54a1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9d55e84d-b4cf-4c53-80c2-3cbdd80e54a1.jsonl
salience: product
status: active
subjects:
  - wiki-research-skill
  - wiki-management-tools
  - skill-gating
  - query-wiki-always-on
supersedes: []
related_claims: []
source_lines:
  - 1466-1483
  - 1493-1528
  - 1612-1620
captured_at: 2026-06-12T11:58:34Z
---

# Episode: Wiki Research Skill: Gate Wiki Management Tools While Keeping query_wiki Always-On

## Prior State

create_wiki_page, list_wiki_pages, and delete_wiki_page were always-on tools in the podcast schema, adding dense schema weight to every conversation even when the user never asks to compile or manage wiki pages.

## Trigger

User asked 'what other set of tools are good candidates to gate behind a skill?' and then directed 'yeah, do wiki' after the assistant identified wiki_research as the strongest candidate, noting that create_wiki_page kicks off a full RAG compile + citation verification and has its own concept space (kind, scope, auto-refresh).

## Decision

Created WikiResearchSkill gating create_wiki_page, list_wiki_pages, and delete_wiki_page. Deliberately kept query_wiki always-on as the cheap lookup path — only the heavy management surface is skill-gated. The skill's manual covers kind (topic/person/show), scope semantics, auto-refresh, AI-key/no-evidence failure modes, and suggested flow (list → upgrade_thinking → create).

## Consequences

- Second built-in skill validates that the skill pattern is reusable across domains
- query_wiki remains always accessible for simple lookups; wiki management requires explicit skill activation
- Reduces the always-on podcast tool schema by removing three dense tool definitions
- The ## Skills section in the system prompt automatically picks up the new skill with no prompt changes needed

## Open Tail

*(none)*

## Evidence

- transcript lines 1466-1483
- transcript lines 1493-1528
- transcript lines 1612-1620

