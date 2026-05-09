import SwiftUI
import os.log

// MARK: - HomeView

/// Editorial podcast landing — the "Today" surface.
///
/// Two stacked sections:
///   • "Continue listening" — horizontal hero rail of in-progress episodes.
///   • "New episodes" — vertical feed of recent unplayed episodes.
///
/// When the user has no subscriptions yet, the screen shows a calm prompt
/// directing them to the Library tab. When they have subscriptions but no
/// episodes (e.g. immediately after import, before the first feed fetch),
/// pull-to-refresh triggers the fetch.
struct HomeView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(PlaybackState.self) private var playback

    private static let logger = Logger.app("HomeView")

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            content
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await refreshAllFeeds() }
        .navigationDestination(for: HomeEpisodeRoute.self) { route in
            EpisodeDetailView(episodeID: route.episodeID)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let inProgress = store.inProgressEpisodes
        let recent = store.recentEpisodes(limit: 30)
        let hasAnyEpisode = !(inProgress.isEmpty && recent.isEmpty)

        // Always wrap in ScrollView so `.refreshable` attaches in every state,
        // including the "subscribed but no episodes yet" pre-first-fetch case
        // where the user most needs to pull down.
        ScrollView {
            if !hasAnyEpisode {
                emptyState
                    .frame(minHeight: 480)
            } else {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg, pinnedViews: []) {
                    if !inProgress.isEmpty {
                        continueListeningSection(inProgress)
                    }
                    if !recent.isEmpty {
                        recentSection(recent)
                    }
                    Color.clear.frame(height: AppTheme.Spacing.lg)
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Continue listening rail

    private func continueListeningSection(_ episodes: [Episode]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            sectionHeader("Continue listening")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    ForEach(episodes) { episode in
                        HomeContinueListeningCard(
                            episode: episode,
                            subscription: store.subscription(id: episode.subscriptionID),
                            onPlay: { playEpisode(episode) }
                        )
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            }
        }
    }

    // MARK: - Recent section

    private func recentSection(_ episodes: [Episode]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            sectionHeader("New episodes")
            VStack(spacing: 0) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    HomeRecentEpisodeRow(
                        episode: episode,
                        subscription: store.subscription(id: episode.subscriptionID),
                        onPlay: { playEpisode(episode) },
                        onMarkPlayed: { markPlayed(episode) }
                    )
                    .padding(.horizontal, AppTheme.Spacing.md)
                    if index < episodes.count - 1 {
                        Divider()
                            .padding(.leading, AppTheme.Spacing.md + 56 + AppTheme.Spacing.md)
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
            )
            .padding(.horizontal, AppTheme.Spacing.md)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.Typography.title3)
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.md)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(AppTheme.Gradients.agentAccent)
                .symbolEffect(.pulse, options: .repeating)
            Text("Today")
                .font(AppTheme.Typography.title)
            Text(emptyStateMessage)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if store.state.subscriptions.isEmpty {
            return "Tap Library to add your first show. Today fills in once you're subscribed."
        }
        return "Pull down to refresh and pick up the latest episodes."
    }

    // MARK: - Actions

    private func playEpisode(_ episode: Episode) {
        Haptics.medium()
        playback.setEpisode(episode)
        playback.play()
    }

    private func markPlayed(_ episode: Episode) {
        Haptics.itemComplete()
        store.markEpisodePlayed(episode.id)
    }

    // MARK: - Refresh

    /// Re-fetches every subscription's feed and merges the new episodes into
    /// the store. Errors per-feed are logged and swallowed so one bad feed
    /// can't kill the entire refresh.
    private func refreshAllFeeds() async {
        let subs = store.sortedSubscriptions
        guard !subs.isEmpty else { return }
        let client = FeedClient()
        for sub in subs {
            do {
                let result = try await client.fetch(sub)
                switch result {
                case .notModified:
                    var refreshed = sub
                    refreshed.lastRefreshedAt = Date()
                    store.updateSubscription(refreshed)
                case .updated(let updatedSub, let episodes, _):
                    store.updateSubscription(updatedSub)
                    store.upsertEpisodes(episodes, forSubscription: updatedSub.id)
                }
            } catch {
                Self.logger.error(
                    "Feed refresh failed for \(sub.title, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
