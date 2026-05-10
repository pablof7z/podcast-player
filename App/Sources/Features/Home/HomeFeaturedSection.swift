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
    /// `true` while the agent service is streaming new picks. Drives the
    /// shimmer placeholder for the *next* pick the model is still emitting
    /// so the user sees the rail filling in incrementally instead of
    /// jumping from empty to fully populated.
    var isStreaming: Bool = false
    /// Top active threading topic. When set, a "Threaded Today" pill renders
    /// below the rail; tapping it invokes `onOpenThread`. `nil` hides the
    /// pill entirely so the section doesn't advertise an empty state.
    var activeThread: ThreadingInferenceService.ActiveTopic? = nil
    @Binding var isExpanded: Bool
    let onPlayEpisode: (Episode) -> Void
    let onLongPressEpisode: (Episode) -> Void
    var onOpenThread: () -> Void = { }

    @Environment(AppStateStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            header
            if isExpanded {
                rail
                if let active = activeThread {
                    HomeThreadedTodayPill(active: active, onTap: onOpenThread)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.xs)
                }
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
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        ))
                    }
                }
                if isStreaming {
                    // Shimmer slot for the next pick still arriving from the
                    // model. We don't know yet whether it'll be a hero or a
                    // secondary, so the placeholder mirrors the secondary
                    // dimensions — the hero (if any) has already streamed
                    // first per the system prompt's ordering rule.
                    HomeAgentPickShimmerCard(isHero: picksBundle.hero == nil)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .animation(AppTheme.Animation.springFast, value: picksBundle.picks.count)
        }
        // Bound height so the rail doesn't push the subscription list off-
        // screen on small phones. The ~280pt budget the brief calls for
        // accommodates resume + pick cards plus their captions.
        .frame(maxHeight: 320)
    }
}
