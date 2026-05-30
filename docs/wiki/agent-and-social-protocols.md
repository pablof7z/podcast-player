---
title: Agent-to-Agent and Social Protocols
slug: agent-and-social-protocols
summary: "Agent-to-agent communication uses public kind:1 notes threaded via NIP-10, matching the win-the-day-app pattern. NIP-17 is an explicit non-goal. NIP-F4 is the canonical podcast publishing protocol."
tags:
  - protocols
  - nostr
  - agents
  - social
  - nips
volatility: warm
confidence: medium
created: 2026-05-29
updated: 2026-05-30
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Agent-to-Agent and Social Protocols

> Agent-to-agent and friend/friend-agent messaging uses public kind:1 notes threaded via NIP-10, not NIP-17. NIP-17 is an explicit non-goal, never appearing as planned work in any doc. NIP-F4 is the canonical production protocol, not a legacy correction from NIP-74; no legacy NIP-74 data migration is needed because NMP is the only implementation.

<!-- citations: [^14943-95] -->
## Agent-to-Agent Communication

Agent-to-agent messaging uses public kind:1 notes threaded via NIP-10, not NIP-17. This matches the reference implementation in `win-the-day-app` (`/Users/pablofernandez/Work/win-the-day-app`), which uses public kind:1 notes with NIP-10 threading for agent interactions. NIP-17 is an explicit non-goal — it should never appear as planned work in any doc, including the backlog, plan, or spec documents.

<!-- citations: [^14943-1] [^14943-91] -->
## Friend and Friend-Agent Messages

Friend DMs and friend-agent messaging use public kind:1 notes threaded via NIP-10, not NIP-17. NIP-17 is an explicit non-goal listed in the identity briefs (`identity-01-minimal.md` and `identity-05-synthesis.md`), and it should never appear as planned work in any doc. The private/encrypted DM question is settled: kind:1 is the decision, with no 'transport TBD' hedging.

<!-- citations: [^14943-2] [^14943-92] -->
## NIP-F4 Canonicality

NIP-F4 is the canonical production protocol, not a legacy correction from NIP-74. It is the right NIP to use and produce. No legacy NIP-74 data migration is needed because NMP is the only implementation. The podcast player's agent-owned podcast publishing path (`docs/features.md`) uses NIP-F4. NIP-74 references survive only as code-symbol names (e.g., `NIP74Show`, `NIP74Episode`) and anti-re-entry test guards that confirm NIP-74 tags are not emitted — these are work items that remove NIP-74, never move toward it.

<!-- citations: [^14943-3] [^14943-93] -->
## Backlog and Plan Corrections

Three framing corrections were applied across `BACKLOG.md`, `plan.md`, `nmp-feature-parity.md`, `pod0-nostr-publishing.md`, `features.md`, and two identity briefs: (1) No legacy data migration is needed — NMP is the only implementation, so the `p0-nipf4-legacy-data` item and all 'legacy-data behavior' mentions were deleted. (2) NIP-F4 is the canonical production protocol, not a legacy correction from NIP-74 — reframed from 'No NIP-74' to 'NIP-F4 is canonical'; the pod0 doc was retitled. (3) Agent-to-agent and friend/friend-agent messaging = kind:1/NIP-10, not NIP-17 — the backlog item and parity row 44 were rewritten; NIP-17 now only appears as a non-goal and should never appear as planned work in any doc. The `migration-v2.md` file was correctly left untouched (its 'legacy' hits are an unrelated OpenRouter key migration).

<!-- citations: [^14943-4] [^14943-94] -->
## See Also
- [[security-and-constraints|Security and Constraints]] — related guide
- [[codex-review-gate|Codex Review Gate]] — related guide

