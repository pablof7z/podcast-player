// Compat shim — replaced when the settings projection lands in nmp-app-podcast.
//
// `Settings` is the legacy domain struct mutated through `state.settings`.
// Only the fields still read or written by Onboarding remain — the Nostr
// identity / profile fields moved off this struct in PR 11 and now live
// in `@AppStorage` (keys `agent.profile.*`) on `AgentIdentityView`. The
// shim survives until the M3 settings projection lands in Rust (see
// `docs/BACKLOG.md` — "M3 — Settings projection").

import Foundation

struct Settings: Equatable, Hashable {
    // Onboarding flag — read in OnboardingView; written in OnboardingView+Handlers.
    var hasCompletedOnboarding: Bool = false

    init() {}

    // MARK: - Mutating helpers

    /// Legacy helper that flipped the OpenRouter credential source after a
    /// manual key save. Compat shim: no-op (credential source not yet
    /// surfaced in the compat struct).
    mutating func markOpenRouterManual() {}
}
