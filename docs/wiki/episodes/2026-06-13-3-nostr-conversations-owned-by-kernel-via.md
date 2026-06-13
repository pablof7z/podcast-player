---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - nostr-conversations-projection
  - podcast-social-domain
  - nip-10-threading
supersedes: []
related_claims: []
source_lines:
  - 7366-7395
  - 7410-7434
  - 7537-7563
captured_at: 2026-06-13T01:31:03Z
---

# Episode: Nostr conversations owned by kernel via podcast.social per-domain projection

## Prior State

Agent notes were a flat list inside podcast.misc domain, with compat-empty conversation/approval surfaces in Swift. The existing ConversationActor/NostrConversation model in podcast-agent-core is explicitly LLM-chat, not peer-Nostr threading.

## Trigger

Architectural design review (Opus) determined the flat agent_notes projection must be replaced by a Rust-owned, NIP-10-threaded conversation projection; explicitly rejected reusing ConversationActor (it's LLM-chat scoped, not peer-Nostr).

## Decision

New podcast.social per-domain typed projection: SocialState.nostr_conversations_snapshot() groups inbound AgentNoteSummary + OutboundTurn entries by rootEventID, merges turns in timestamp order, sorts conversations newest-first, computes trusted live against follow set. build_misc_payload drops social/agent_notes (atomic move, no duplication). SocialDomainFrame has no explicit CodingKeys (convertFromSnakeCase contract). OutboundTurnCache (bounded ring MAX=200, crash-safe atomic tmp-rename write) persists outbound responder turns. iOS KernelModel+DomainMerge maps wire rootEventId → domain rootEventID. Existing NostrConversationsView auto-lights-up. Android wire parity with @SerialName. Tombstone-on-empty contract for social domain.

## Consequences

- Opus review caught a BLOCKER: domain_revs.social had zero production writers (dormant scaffolding, 3rd recurrence of this pattern: #399, #400, #423)
- The misc→social move must be atomic — build_misc_payload must not re-emit social/agent_notes
- convertFromSnakeCase: no explicit CodingKeys on SocialDomainFrame (same contract as #371 fix)
- recordNostrTurn marked LEGACY — deletable once kernel push is confirmed live end-to-end

## Open Tail

- PR #423 in-flight: blocker fix (real Domain::Social bump at both mutation sites) + iOS #371 decode test being applied
- Android PodcastSnapshot can gain nostrConversations field when Android UI surfaces the view

## Evidence

- transcript lines 7366-7395
- transcript lines 7410-7434
- transcript lines 7537-7563

