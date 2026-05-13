import Foundation

// MARK: - HomeInboxBundle
//
// Composes the Home "Inbox" section's hero + secondaries view-model from
// the persisted AI triage decisions on `state.episodes`. The Inbox UI is
// the same Featured layout that previously read from `AgentPicksService`
// — we just swap the data source so the picks are persistent agent
// decisions (with rationale) instead of an ephemeral curation cache.
//
// Hero rank is by recency: the most recently published `.inbox` episode
// is the hero, the next four become secondaries. That keeps the surface
// freshness-biased without introducing another scoring axis the agent
// would have to reason about.

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
        let inbox = store.state.episodes
            .lazy
            .filter { episode in
                guard episode.triageDecision == .inbox else { return false }
                // Triage marks `.inbox` even after the user has started
                // listening; once they finish the episode it should drop
                // off the surface. `played` covers the explicit case;
                // very-near-end positions are still surfaced (no special
                // case here).
                if episode.played { return false }
                if let allowed = allowedSubscriptionIDs,
                   !allowed.contains(episode.podcastID) {
                    return false
                }
                return true
            }
            .sorted { $0.pubDate > $1.pubDate }

        var picks: [HomeAgentPick] = []
        picks.reserveCapacity(1 + secondariesCap)

        var iterator = inbox.makeIterator()
        if let hero = iterator.next() {
            picks.append(HomeAgentPick(
                episodeID: hero.id,
                rationale: hero.triageRationale ?? "",
                spokenRationale: "",
                isHero: true
            ))
            var counted = 0
            while counted < secondariesCap, let next = iterator.next() {
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
