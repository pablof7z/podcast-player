---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - podcast-social-domain
  - nip-10-conversations
  - conversation-actor-non-reuse
supersedes:
  - 2026-06-13-4-podcast-social-domain-rust-owned-nip
related_claims: []
source_lines:
  - 7336-7368
  - 7372-7388
  - 7410-7435
  - 7455-7504
captured_at: 2026-06-13T02:14:15Z
---

# Episode: podcast.social domain replaces misc blob for social/agent_notes, with new NIP-10 conversation model

## Prior State

Social data (agent_notes, conversations) rode the podcast.misc monolithic blob. The BACKLOG assumed ConversationActor/NostrConversation would be the canonical model for NIP-10 threads. NostrConversationsView in Swift was compat-empty.

## Trigger

Opus architect verified that ConversationActor/NostrConversation is explicitly LLM-chat, not peer-Nostr (its own doc comment says so). The misc blob needed decomposition for performance and correctness. BACKLOG item nostr-conversations-real-projection specified replacing compat-empty surfaces with Rust-owned projection.

## Decision

Created the podcast.social domain as the 8th per-domain delta sidecar. Built a new Rust-owned NIP-10 conversation projection (SocialState.nostr_conversations_snapshot()) that groups AgentNoteSummary + OutboundTurn by root_event_id, merges turns in timestamp order, sorts conversations newest-first, and computes trust live against the follow set. The misc blob no longer emits social/agent_notes fields. Swift bridge uses SocialDomainFrame with no explicit CodingKeys (snake_case contract), mapping rootEventId → rootEventID at the merge layer.

## Consequences

- build_misc_payload no longer emits agent_notes or social fields — clean move, not duplication
- NostrConversationsView lights up automatically via projectSnapshotDerivedState
- OutboundTurnCache is durable (bounded ring, MAX=200, atomic tmp-rename write)
- recordNostrTurn marked LEGACY for eventual deletion once kernel push confirmed end-to-end
- Android DomainFrameWireTest + schema-constants updated; Android UI needs nostrConversations field when it surfaces the view
- Golden fixture byte-identical (skip_serializing_if Vec::is_empty)

## Open Tail

- Android PodcastSnapshot can gain nostrConversations field when Android UI surfaces this view
- recordNostrTurn (LEGACY) can be deleted once kernel push confirmed live

## Evidence

- transcript lines 7336-7368
- transcript lines 7372-7388
- transcript lines 7410-7435
- transcript lines 7455-7504

