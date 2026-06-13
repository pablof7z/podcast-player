---
type: episode-card
date: 2026-05-12
session: 9d55e84d-b4cf-4c53-80c2-3cbdd80e54a1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9d55e84d-b4cf-4c53-80c2-3cbdd80e54a1.jsonl
salience: architecture
status: active
subjects:
  - agent-skills
  - tool-gating
  - use-skill-meta-tool
  - context-budget
supersedes: []
related_claims: []
source_lines:
  - 1-3
  - 541-548
  - 550-569
  - 741-767
  - 771-778
  - 803-870
captured_at: 2026-06-12T11:58:34Z
---

# Episode: Agent Skills System: Conditional Tool Surface via use_skill Meta-Tool

## Prior State

All podcast-domain tools (including generate_tts_episode, configure_agent_voice) were always present in the agent's tool schema; the system prompt always carried a TTS instruction paragraph. No mechanism existed to conditionally inject tools or knowledge — the agent saw everything on every turn regardless of relevance.

## Trigger

User directive (line 1-3): 'let's give a skill tool to the agent… a tool (gated by the agent enabling the skill) that gives it knowledge… the goal is to provide some built-in skills to the agent with stuff that requires some tools that might not be always useful so we can focus the agent with tools and knowledge on how to perform certain tasks.'

## Decision

Introduced a Skills architecture: (1) `use_skill` meta-tool added to the always-on schema — the agent calls it to activate a skill by ID; (2) `AgentSkill` value type holds an id, summary, manual, and schema closure; (3) `AgentSkillRegistry` catalogs all skills and provides a shared `activate()` contract; (4) both turn loops (AgentChatSession and AgentRelayBridge) intercept `use_skill` in-band (same pattern as `upgrade_thinking`), append per-skill schemas to the LLM tool list, and thread `enabledSkills` into dispatch; (5) `enabledSkills: Set<String>` persists on the session and in `ChatConversation` with `decodeIfPresent` backwards-compatible decoding; (6) re-activation skips re-sending the manual to save context tokens.

## Consequences

- New architectural doctrine: any future capability that is heavy or niche must be packaged as a skill rather than always-on tools
- The agent must explicitly opt into capabilities via use_skill, changing visible behavior — it will no longer see TTS or wiki-management tools by default
- System prompt now ends with a ## Skills catalog section listing each registered skill's id and summary
- dispatchPodcast defensively rejects skill-gated tools when the owning skill isn't enabled
- Reduced context/token budget on every turn that doesn't invoke a skill

## Open Tail

- Full simulator smoke test of use_skill → list_available_voices → generate_tts_episode flow not yet exercised against a live LLM

## Evidence

- transcript lines 1-3
- transcript lines 541-548
- transcript lines 550-569
- transcript lines 741-767
- transcript lines 771-778
- transcript lines 803-870

