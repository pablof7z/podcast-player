---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - nostr-conversations-projection
  - social-domain
  - conversation-model
supersedes: []
related_claims: []
source_lines:
  - 7374-7383
  - 7419-7431
  - 7455-7476
captured_at: 2026-06-13T02:30:19Z
---

# Episode: Conversation projection uses new SocialState model, not LLM-chat ConversationActor

## Prior State

BACKLOG suggested reusing podcast-agent-core::ConversationActor/NostrConversation for the new NIP-10 peer-Nostr conversation surface.

## Trigger

Opus architect verified the existing ConversationActor model is explicitly LLM-chat (its own doc comment says so), not peer-Nostr. Its fields and semantics are wrong for threaded public-note conversations.

## Decision

Build a new SocialState.nostr_conversations_snapshot() as the single source of truth — groups inbound AgentNoteSummary and outbound OutboundTurn entries by root_event_id, merges turns in timestamp order, sorts newest-first, and computes trusted against the follow set. Carried on the new podcast.social domain sidecar.

## Consequences

- The misc→social move is clean: build_misc_payload no longer emits social/agent_notes fields
- OutboundTurnCache is durable (bounded ring at MAX=200, dedup by event_id, evict-oldest, atomic tmp-rename write)
- iOS bridge uses SocialDomainFrame with no explicit CodingKeys; nostrConversationFromDTO maps rootEventId→rootEventID, Int→Date, string→Direction enum
- The existing NostrConversationsView was rewired to consume the new kernel-projected conversations automatically

## Open Tail

- recordNostrTurn (marked LEGACY) can be deleted once the kernel push is confirmed live end-to-end
- Android PodcastSnapshot can gain a nostrConversations field when the Android UI surfaces this view

## Evidence

- transcript lines 7374-7383
- transcript lines 7419-7431
- transcript lines 7455-7476

