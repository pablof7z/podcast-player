import SwiftUI

// MARK: - HomeFeaturedSection

/// The collapsible featured strip at the top of merged Home. Houses both
/// resume cards (in-progress episodes) and agent picks (hero + secondaries).
/// Default expanded with ~280pt height; collapsed state shows just the
/// section header so the user can dismiss the curated surface and get
/// straight to the subscription list below.
struct HomeFeaturedSection: View {
    let resumeEpisodes: [Episode]
    let picksBundle: HomeAgentPicksBundle
    @Binding var isExpanded: Bool
    let onPlayEpisode: (Episode) -> Void
    let onLongPressEpisode: (Episode) -> Void

    @Environment(AppStateStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            header
            if isExpanded {
                rail
            }
        }
    }

    private var header: some View {
        Button {
            Haptics.selection()
            withAnimation(AppTheme.Animation.springFast) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("Featured")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(.primary)
                if picksBundle.source == .fallback && !picksBundle.picks.isEmpty {
                    // Honest disclosure when the agent fallback heuristic
                    // produced the picks rather than a real LLM call. The
                    // user shouldn't believe the agent picked these if it
                    // didn't.
                    Text("Heuristic")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppTheme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Featured, expanded" : "Featured, collapsed")
        .accessibilityHint("Double tap to toggle")
    }

    @ViewBuilder
    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                ForEach(resumeEpisodes) { ep in
                    HomeResumeCard(
                        episode: ep,
                        subscription: store.subscription(id: ep.subscriptionID),
                        onPlay: { onPlayEpisode(ep) }
                    )
                    // Long-press → "find related" sheet. We can't add a
                    // `.contextMenu(menuItems:preview:)` and a long-press
                    // handler in parallel without one swallowing the other,
                    // so the related-search affordance lives on a
                    // simultaneous gesture instead — onLongPressGesture
                    // fires once the menu would have been about to open.
                    .onLongPressGesture(minimumDuration: 0.6) {
                        Haptics.medium()
                        onLongPressEpisode(ep)
                    }
                }
                if let hero = picksBundle.hero,
                   let episode = store.episode(id: hero.episodeID) {
                    HomeAgentPickCard(
                        pick: hero,
                        episode: episode,
                        subscription: store.subscription(id: episode.subscriptionID),
                        isHero: true,
                        onPlay: { onPlayEpisode(episode) }
                    )
                    .onLongPressGesture(minimumDuration: 0.6) {
                        Haptics.medium()
                        onLongPressEpisode(episode)
                    }
                }
                ForEach(picksBundle.secondaries) { pick in
                    if let episode = store.episode(id: pick.episodeID) {
                        HomeAgentPickCard(
                            pick: pick,
                            episode: episode,
                            subscription: store.subscription(id: episode.subscriptionID),
                            isHero: false,
                            onPlay: { onPlayEpisode(episode) }
                        )
                        .onLongPressGesture(minimumDuration: 0.6) {
                            Haptics.medium()
                            onLongPressEpisode(episode)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        }
        // Bound height so the rail doesn't push the subscription list off-
        // screen on small phones. The ~280pt budget the brief calls for
        // accommodates resume + pick cards plus their captions.
        .frame(maxHeight: 320)
    }
}
