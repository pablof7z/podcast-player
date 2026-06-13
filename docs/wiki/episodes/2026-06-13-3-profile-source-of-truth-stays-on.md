---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: active
subjects:
  - kind0-hydration
  - resolved-profiles
  - single-source-of-truth
supersedes: []
related_claims: []
source_lines:
  - 8129-8132
captured_at: 2026-06-13T03:58:09Z
---

# Episode: Profile source-of-truth stays on resolved_profiles — no duplication in conversation projection

## Prior State

The cycle-9 planner specified kind:0 profile hydration inside the podcast.social projection as part of the conversations completeness vertical, implying a new profile cache within the Rust social domain.

## Trigger

Design-pass investigation found that iOS already has a complete resolved_profiles seam: claimProfile (KernelModel.swift:731) → kernel resolves → projections.resolved_profiles → mergeResolvedProfiles (AppStateStore+KernelProjection.swift:462) → nostrProfileCache, and NostrConversationsView.swift:38 + NostrConversationDetailView.swift:21 already read from nostrProfileCache[hex].

## Decision

Do NOT hydrate kind:0 profiles inside the conversation projection. Ride the existing resolved_profiles seam instead — duplicating profile data into podcast.social would create a second profile cache and violate single-source-of-truth. The tiny follow-up is to have the views call claimProfile(counterpartyHex) on appear if not already resolved.

## Consequences

- No new profile storage or projection field in the Rust social domain
- No snake_case/golden churn for a profile sub-field
- kind:0 hydration remains out of v1 scope — the existing seam already works

## Open Tail

- Add claimProfile(counterpartyHex) on view-appear for the rare case where a profile hasn't been resolved yet

## Evidence

- transcript lines 8129-8132

