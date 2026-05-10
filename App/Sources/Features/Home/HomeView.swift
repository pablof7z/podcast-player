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

    /// Drives the VoiceOver "Open episode details" custom action surfaced by
    /// every Home episode row/card. `accessibilityActions` cannot host a
    /// `NavigationLink`, so we route through `.navigationDestination(item:)`.
    @State private var voiceOverDetailRoute: HomeEpisodeRoute?

    var body: some View {
        content
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await refreshAllFeeds() }
            .navigationDestination(for: HomeEpisodeRoute.self) { route in
                EpisodeDetailView(episodeID: route.episodeID)
            }
            .navigationDestination(item: $voiceOverDetailRoute) { route in
                EpisodeDetailView(episodeID: route.episodeID)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let inProgress = store.inProgressEpisodes
        let recent = store.recentEpisodes(limit: 30)
        let hasAnyEpisode = !(inProgress.isEmpty && recent.isEmpty)

        if !hasAnyEpisode {
            // Wrap the empty state in a ScrollView so `.refreshable` still
            // attaches in the "subscribed but no episodes yet" case where the
            // user most needs to pull down.
            ScrollView {
                emptyState.frame(minHeight: 480)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        } else {
            List {
                if !inProgress.isEmpty {
                    continueListeningRow(inProgress)
                }
                if !recent.isEmpty {
                    recentSection(recent)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    // MARK: - Continue listening rail

    private func continueListeningRow(_ episodes: [Episode]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                sectionHeader("Continue listening")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        ForEach(episodes) { episode in
                            HomeContinueListeningCard(
                                episode: episode,
                                subscription: store.subscription(id: episode.subscriptionID),
                                onPlay: { playEpisode(episode) },
                                voiceOverDetailRoute: $voiceOverDetailRoute
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .padding(.top, AppTheme.Spacing.sm)
        }
    }

    // MARK: - Recent section

    @ViewBuilder
    private func recentSection(_ episodes: [Episode]) -> some View {
        Section {
            sectionHeader("New episodes")
                .listRowInsets(EdgeInsets(
                    top: AppTheme.Spacing.sm,
                    leading: 0,
                    bottom: AppTheme.Spacing.xs,
                    trailing: 0
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(episodes) { episode in
                HomeRecentEpisodeRow(
                    episode: episode,
                    subscription: store.subscription(id: episode.subscriptionID),
                    onPlay: { playEpisode(episode) },
                    voiceOverDetailRoute: $voiceOverDetailRoute
                )
                .listRowInsets(EdgeInsets(
                    top: AppTheme.Spacing.xs,
                    leading: AppTheme.Spacing.md,
                    bottom: AppTheme.Spacing.xs,
                    trailing: AppTheme.Spacing.md
                ))
                // Hairline separator between rows — replaces the manual
                // `Divider()` from the previous LazyVStack layout.
                .listRowSeparator(.visible)
                .listRowSeparatorTint(AppTheme.Tint.hairline)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    EpisodeRowLeadingSwipeAction(episode: episode, playback: playback)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    EpisodeRowTrailingSwipeAction(episode: episode, store: store)
                    EpisodeRowDownloadSwipeAction(episode: episode, store: store)
                }
            }
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

    // MARK: - Refresh

    /// Re-fetches every subscription's feed in parallel and merges the
    /// new episodes into the store. Errors per-feed are logged and
    /// swallowed so one bad feed can't kill the entire refresh.
    ///
    /// Fetch is fan-out via TaskGroup because each request is bound by
    /// network latency and there are no cross-feed dependencies; the
    /// store mutations are then applied serially on the main actor so
    /// the observable writes remain ordered.
    private func refreshAllFeeds() async {
        let subs = store.sortedSubscriptions
        guard !subs.isEmpty else { return }
        let client = FeedClient()
        // Capture the logger up front — `Self.logger` is implicitly
        // main-actor isolated through the View, but `os.Logger` is
        // Sendable, so a captured copy can be safely used from the
        // detached fetch tasks.
        let logger = Self.logger

        // Each task returns the subscription it was responsible for
        // alongside its outcome. `nil` means an error was already
        // logged inside the task — surfaced as a no-op below.
        let outcomes = await withTaskGroup(
            of: (PodcastSubscription, FeedClient.FeedFetchResult?).self
        ) { group in
            for sub in subs {
                group.addTask {
                    do {
                        let result = try await client.fetch(sub)
                        return (sub, result)
                    } catch {
                        logger.error(
                            "Feed refresh failed for \(sub.title, privacy: .public): \(String(describing: error), privacy: .public)"
                        )
                        return (sub, nil)
                    }
                }
            }
            var collected: [(PodcastSubscription, FeedClient.FeedFetchResult?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (sub, result) in outcomes {
            guard let result else { continue }
            switch result {
            case .notModified:
                var refreshed = sub
                refreshed.lastRefreshedAt = Date()
                store.updateSubscription(refreshed)
            case .updated(let updatedSub, let episodes, _):
                store.updateSubscription(updatedSub)
                store.upsertEpisodes(
                    episodes,
                    forSubscription: updatedSub.id,
                    evaluateAutoDownload: true
                )
            }
        }
    }
}
