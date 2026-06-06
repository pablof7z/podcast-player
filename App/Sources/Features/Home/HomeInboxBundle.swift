import Foundation

// MARK: - HomeInboxBundle
//
// Composes the Home "Inbox" section's hero + secondaries view-model from
// the persisted AI triage decisions on `state.episodes`. This is distinct
// from the "Recommended for you" rail, which renders Rust-projected
// `PodcastUpdate.picks` directly.
//
// Hero rank prefers the agent's explicit `triageIsHero` flag — the
// LLM is allowed to crown one inbox pick per pass as the editorial
// lead. When no episode is flagged, fall back to the most recently
// published `.inbox` episode so the surface still has a hero.

@MainActor
enum HomeInboxBundleBuilder {

    /// Max secondaries surfaced below the hero card. Kept stable so layout
    /// assumptions in `HomeFeaturedSection` stay valid.
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
        let inbox = store.episodes
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

        // Hero precedence: agent-crowned `triageIsHero` wins; fall back
        // to newest pubDate (already first after the sort above).
        let heroEpisode = inbox.first(where: { $0.triageIsHero }) ?? inbox.first
        var picks: [HomeAgentPick] = []
        picks.reserveCapacity(1 + secondariesCap)
        if let hero = heroEpisode {
            picks.append(HomeAgentPick(
                episodeID: hero.id,
                rationale: hero.triageRationale ?? "",
                spokenRationale: "",
                isHero: true
            ))
            var counted = 0
            for next in inbox where next.id != hero.id {
                if counted >= secondariesCap { break }
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
