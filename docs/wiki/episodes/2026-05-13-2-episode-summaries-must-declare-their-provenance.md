---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: architecture
status: active
subjects:
  - summary-provenance
  - episode-summarizer
  - agent-transparency
supersedes: []
related_claims: []
source_lines:
  - 506-533
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Episode summaries must declare their provenance

## Prior State

When an LLM summary was unavailable, the system silently fell back to the publisher's episode description with no indication to the agent or user that the text was not AI-generated.

## Trigger

Audit identified that LiveEpisodeSummarizerAdapter returned publisher descriptions as if they were LLM summaries — the agent had no way to communicate the distinction.

## Decision

Added SummarySource enum (.llm / .publisherDescription / .unavailable) to EpisodeSummary; all four return sites in the adapter tagged explicitly; tool result JSON now includes "summary_source": "publisherDescription" (or other).

## Consequences

- LLM can now tell the user 'this is the publisher's description, not an AI summary' when appropriate
- UI code rendering summary.summary is unchanged — provenance is for the agent layer
- Backward-compatible: source defaults to .llm so existing call sites without explicit source don't break

## Open Tail

- UI could eventually surface a visual distinction between AI and publisher summaries

## Evidence

- transcript lines 506-533

