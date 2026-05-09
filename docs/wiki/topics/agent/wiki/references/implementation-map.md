---
title: "Implementation Map"
category: references
sources:
  - raw/notes/2026-05-09-agent-source-map.md
created: 2026-05-09
updated: 2026-05-09
tags: [implementation, swift, agent, files]
aliases: [Agent Implementation Placement]
confidence: medium
volatility: warm
verified: 2026-05-09
summary: "Agent additions should extend existing AgentTools, AgentPrompt, AgentRelayBridge, Voice, Briefing, and Knowledge modules instead of creating a separate agent extension layer."
---

# Implementation Map

Agent work should follow the current codebase shape.

## Existing Areas To Extend

- `App/Sources/Agent/AgentPrompt.swift` - prompt inventory and handle strategy.
- `App/Sources/Agent/AgentToolSchema.swift` - schema entries for new tools.
- `App/Sources/Agent/AgentTools.swift` - shared dispatch routing.
- `App/Sources/Agent/AgentTools+Podcast.swift` - playback and episode tools.
- `App/Sources/Agent/AgentTools+RAG.swift` - transcript retrieval.
- `App/Sources/Agent/AgentTools+Wiki.swift` - compiled wiki lookup.
- `App/Sources/Agent/AgentTools+Briefing.swift` - briefing generation.
- `App/Sources/Agent/AgentTools+Web.swift` - external research.
- `App/Sources/Agent/AgentRelayBridge.swift` - Nostr inbound loop and remote safety gates.
- `App/Sources/Voice/AudioConversationManager.swift` - voice orchestration.
- `App/Sources/Briefing/BriefingComposer.swift` - briefing scripts and anchors.
- `App/Sources/Knowledge/` - wiki, embeddings, and retrieval services.

## File Length Rule

Keep each concern split before it approaches the 300-line soft limit. The tool files should be grouped by domain, not by one giant podcast-agent file.

## See Also

- [[tool-surface|Tool Surface]] ([Tool Surface](../concepts/tool-surface.md)) - tool domains that map to these files.
- [[data-model-notes|Data Model Notes]] ([Data Model Notes](../../../knowledge/wiki/references/data-model-notes.md)) - persistence boundaries for tool implementations.

## Sources

- [Agent source map](../../raw/notes/2026-05-09-agent-source-map.md)
