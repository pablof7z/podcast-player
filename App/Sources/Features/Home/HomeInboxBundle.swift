import Foundation

// MARK: - HomeInboxBundle
//
// Composes the Home "Inbox" section's hero + secondaries view-model from
// the persisted AI triage decisions on `state.episodes`. The Inbox UI is
// the same Featured layout that previously read from `AgentPicksService`
// — we just swap the data source so the picks are persistent agent
// decisions (with rationale) instead of an ephemeral curation cache.
//
// Hero rank prefers the agent's explicit `triageIsHero` flag — the
// LLM is allowed to crown one inbox pick per pass as the editorial
// lead. When no episode is flagged, fall back to the most recently
// published `.inbox` episode so the surface still has a hero.

@MainActor
enum HomeInboxBundleBuilder {

    /// Max secondaries surfaced below the hero card. Mirrors the cap the
    /// previous `AgentPicksService` honoured so layout assumptions in
    /// `HomeFeaturedSection` stay valid.
    static let secondariesCap = 4

    /// Compose the bundle from the store. `allowedSubscriptionIDs` is
    /// the active-category filter (`nil` = All Categories) — when set,
    /// only inbox decisions from podcasts in that subscription set
    /// surface, so the magazine-section UX still works inside Inbox.
    static func make(
        store: AppStateStore,
        allowedSubscriptionIDs: Set<UUID>?,
        now: Date = Date()
    ) -> HomeAgentPicksBundle {
        let inboxIDs = store.inboxEpisodeIDs(allowedSubscriptionIDs: allowedSubscriptionIDs)

        // Hero precedence: agent-crowned `triageIsHero` wins; fall back
        // to newest pubDate (the projection is already newest first).
        let heroID = inboxIDs.first { store.episode(id: $0)?.triageIsHero == true }
            ?? inboxIDs.first
        var picks: [HomeAgentPick] = []
        picks.reserveCapacity(1 + secondariesCap)
        if let heroID, let hero = store.episode(id: heroID) {
            picks.append(HomeAgentPick(
                episodeID: hero.id,
                rationale: hero.triageRationale ?? "",
                spokenRationale: "",
                isHero: true
            ))
            var counted = 0
            for nextID in inboxIDs where nextID != hero.id {
                if counted >= secondariesCap { break }
                guard let next = store.episode(id: nextID) else { continue }
                picks.append(HomeAgentPick(
                    episodeID: next.id,
                    rationale: next.triageRationale ?? "",
                    spokenRationale: "",
                    isHero: false
                ))
                counted += 1
            }
        }

        return HomeAgentPicksBundle(
            picks: picks,
            source: .agent,
            generatedAt: now
        )
    }
}
