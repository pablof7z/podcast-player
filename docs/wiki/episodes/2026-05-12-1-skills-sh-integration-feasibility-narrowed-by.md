---
type: episode-card
date: 2026-05-12
session: 4be65570-62ca-4bde-8089-764e01ac9804
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4be65570-62ca-4bde-8089-764e01ac9804.jsonl
salience: product
status: active
subjects:
  - agent-skills
  - skills-sh-integration
  - tool-surface
supersedes: []
related_claims: []
source_lines:
  - 1-143
captured_at: 2026-06-12T11:59:28Z
---

# Episode: Skills.sh Integration Feasibility Narrowed by Tool-Surface Mismatch

## Prior State

The user expected skills.sh skills could be installed via the existing use_skill mechanism to extend the agent with useful third-party capabilities, analogous to how Claude Code consumes skills.sh.

## Trigger

Investigation of AgentTools.schema revealed the agent lacks Bash/Read/Write/WebFetch — it only has ~15 app-specific tools (playEpisodeAt, pausePlayback, addToQueue, etc.). Most skills.sh skills assume CLI-level tools, making them inert in this runtime.

## Decision

Skills.sh's distribution format and plumbing can be reused, but the catalog must be curated to contain skills written against this app's specific tool surface. Direct consumption of the existing skills.sh catalog is infeasible as-is.

## Consequences

- Remote/installable skills are constrained to instructions-only (no new tool schemas at runtime) — they compose existing app tools like searchEpisodes + addToQueue
- Third-party skill loading introduces prompt-injection risk; requires a curated allowlist or signed manifest before any fetch-and-inject flow ships
- Session persistence of remote skills needs different handling than built-in skills (not persisted into ChatConversation without trust gate)
- The realistic integration is a curated, app-specific skill catalog using skills.sh's markdown+frontmatter format, not the public skills.sh feed

## Open Tail

- Concrete design for install_skill_from_url meta-tool not yet sketched
- Allowlist/curation mechanism for third-party skills undefined

## Evidence

- transcript lines 1-143

