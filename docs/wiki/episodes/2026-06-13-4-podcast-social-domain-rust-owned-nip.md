---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - nostr-conversations-projection
  - podcast-social-domain
  - outbound-turn-cache
supersedes:
  - 2026-06-13-3-nostr-conversations-owned-by-kernel-via
related_claims: []
source_lines:
  - 7366-7388
  - 7415-7433
  - 7536-7560
  - 7599-7628
captured_at: 2026-06-13T01:45:27Z
---

# Episode: Podcast.social domain: Rust-owned NIP-10 conversation projection

## Prior State

NostrConversationsView in Swift consumed a compat-empty surface. agent_notes were in the misc blob domain with no conversation threading. The existing ConversationActor/NostrConversation model existed but was explicitly LLM-chat, not peer-Nostr.

## Trigger

BACKLOG item nostr-conversations-real-projection. Architectural review confirmed ConversationActor must NOT be reused (its own doc comment says it's LLM-chat, not peer-Nostr). User mandated durable architecture.

## Decision

New podcast.social per-domain delta sidecar (8th domain). SocialState.nostr_conversations_snapshot() groups inbound AgentNoteSummary + OutboundTurn entries by root_event_id, merges turns by timestamp, sorts conversations newest-first, computes trusted live against follow set. agent_notes and nostr_conversations MOVED from misc to social domain (no duplication). OutboundTurnCache is durable (bounded ring, MAX=200, crash-safe atomic tmp-rename). iOS bridge uses typed SocialDomainFrame with nostrConversationFromDTO mapping (rootEventId camelCase DTO → rootEventID uppercase domain model — deliberate mapping, not a #371 landmine). NostrConversationsView lights up automatically via projectSnapshotDerivedState.

## Consequences

- misc domain no longer carries social/agent_notes — build_misc_payload confirmed clean
- 8th domain sidecar registered alongside the existing 7
- All production mutation sites use Infra::bump() (the blocker class caught by Opus review and fixed before merge)
- Real-path observer tests guard the domain-rev advancement; manual counter bumps eliminated
- iOS decode test (NostrConversationSocialDomainTests) guards the #371 snake_case contract
- skip_serializing_if = Vec::is_empty keeps golden fixture byte-identical when social is empty

## Open Tail

- Android PodcastSnapshot can gain a nostrConversations field when the Android UI surfaces this view
- recordNostrTurn (now marked LEGACY) can be deleted once kernel push is confirmed live end-to-end

## Evidence

- transcript lines 7366-7388
- transcript lines 7415-7433
- transcript lines 7536-7560
- transcript lines 7599-7628

