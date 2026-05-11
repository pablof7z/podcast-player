import SwiftUI

/// Full-screen Now Playing surface.
///
/// Layout: compact episode header (artwork left, title/show/metadata right) →
/// chapters → semantic waveform → primary transport → action cluster. Colors
/// and fonts use semantic / Dynamic Type styles so the surface adapts to the
/// user's appearance settings and accent color.
struct PlayerView: View {

    @Environment(AppStateStore.self) private var store
    @Bindable var state: PlaybackState
    @Environment(\.dismiss) private var dismiss
    let glassNamespace: Namespace.ID

    @State private var isScrubbing: Bool = false
    @State private var showSpeedSheet: Bool = false
    @State private var showSleepSheet: Bool = false
    @State private var showShareSheet: Bool = false

    /// Observed so the editorial-header download badge tracks the service's
    /// `progress[id]` map at 5%/200ms without each tick re-rendering through
    /// `AppStateStore`. Mirrors the pattern used by `EpisodeRow`.
    @State private var downloadService = EpisodeDownloadService.shared

    private var subscription: PodcastSubscription? {
        guard let subID = state.episode?.subscriptionID else { return nil }
        return store.subscription(id: subID)
    }

    private var showName: String {
        subscription?.title ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    episodeHeader
                    secondarySurface
                        .frame(minHeight: 240, maxHeight: 320)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            }

            playbackChrome
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PlayerEditorialBackdrop(artworkURL: artworkURL)
        }
        .sheet(isPresented: $showSpeedSheet) { PlayerSpeedSheet(state: state) }
        .sheet(isPresented: $showSleepSheet) { PlayerSleepTimerSheet(state: state) }
        .sheet(isPresented: $showShareSheet) {
            if let episode = state.episode {
                PlayerShareSheet(state: state, episode: episode, showName: showName)
            }
        }
        .task(id: state.episode?.id) {
            if let episode = state.episode {
                ChaptersHydrationService.shared.hydrateIfNeeded(
                    episode: episode,
                    store: store
                )
                await AIChapterCompiler.shared.compileIfNeeded(
                    episodeID: episode.id,
                    store: store
                )
                await AdSegmentDetector.shared.detectIfNeeded(
                    episodeID: episode.id,
                    store: store
                )
            }
            AutoSnipController.shared.attach(playback: state, store: store)
        }
        .overlay(alignment: .top) {
            AutoSnipBanner(controller: AutoSnipController.shared)
                .padding(.top, AppTheme.Spacing.lg)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Minimize player")
            .accessibilityHint("Returns to the previous screen")

            Spacer()

            if !showName.isEmpty {
                Text(showName)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, AppTheme.Spacing.sm)
            }

            Spacer()

            HStack(spacing: AppTheme.Spacing.xs) {
                if state.episode != nil {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Share episode")
                }

                topBarRoutePicker

                if let episode = state.episode {
                    PlayerMoreMenu(
                        episode: episode,
                        subscription: subscription,
                        onMarkPlayed: { store.markEpisodePlayed(episode.id) },
                        onMarkUnplayed: { store.markEpisodeUnplayed(episode.id) },
                        onDismissPlayer: { dismiss() },
                        onShowSleepTimer: { showSleepSheet = true }
                    )
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
    }

    /// Audio-output route picker styled to match the top-bar glass buttons.
    private var topBarRoutePicker: some View {
        ZStack {
            Image(systemName: "airplayaudio")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityHidden(true)
            RoutePickerView(activeTintColor: .clear, tintColor: .clear)
                .allowsHitTesting(true)
                .accessibilityHidden(true)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio output")
        .accessibilityHint("Opens system output picker")
    }

    // MARK: - Episode header (compact: artwork left, text right)

    /// Resolved artwork URL with per-chapter override. Priority:
    ///   1. Active chapter's `imageURL`
    ///   2. Per-episode artwork (`<itunes:image>` override)
    ///   3. Show-level cover art via `PlaybackState.resolveShowImage`
    private var artworkURL: URL? {
        guard let episode = state.episode else { return nil }
        if let chapterImage = activeChapterImageURL { return chapterImage }
        return episode.imageURL ?? state.resolveShowImage(episode)
    }

    private var activeChapterImageURL: URL? {
        guard let chapters = navigableChapters, !chapters.isEmpty else { return nil }
        return chapters.active(at: state.currentTime)?.imageURL
    }

    private var episodeHeader: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            compactArtwork
            if let episode = state.episode {
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title.uppercased())
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !showName.isEmpty {
                        Text(showName)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if !metadataLine.isEmpty {
                        Text(metadataLine)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    downloadBadge
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactArtwork: some View {
        ZStack {
            if let url = artworkURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        compactArtworkFallback
                    }
                }
                .id(url)
                .transition(.opacity)
            } else {
                compactArtworkFallback
            }
        }
        .frame(width: 110, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        .blur(radius: isScrubbing ? 4 : 0)
        .glassEffectID("player.artwork", in: glassNamespace)
        .animation(AppTheme.Animation.spring, value: isScrubbing)
        .animation(.easeInOut(duration: 0.35), value: artworkURL)
        .accessibilityHidden(true)
    }

    private var compactArtworkFallback: some View {
        ZStack {
            Color.secondary.opacity(0.10)
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private var metadataLine: String {
        guard let episode = state.episode else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        let date = f.string(from: episode.pubDate)
        if let duration = episode.duration {
            let mins = Int(duration / 60)
            let h = mins / 60
            let m = mins % 60
            let durString = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            return "\(date) · \(durString)"
        }
        return date
    }

    // MARK: - Secondary surface (chapters only)

    @ViewBuilder
    private var secondarySurface: some View {
        if let chapters = navigableChapters, !chapters.isEmpty {
            PlayerChaptersScrollView(
                chapters: chapters,
                state: state,
                useGlassCard: true
            )
        } else {
            PlayerNoChaptersPlaceholder(episode: liveEpisode)
        }
    }

    private var liveEpisode: Episode? {
        guard let id = state.episode?.id else { return nil }
        return store.episode(id: id) ?? state.episode
    }

    private var navigableChapters: [Episode.Chapter]? {
        let liveEpisode = state.episode.flatMap { store.episode(id: $0.id) } ?? state.episode
        return liveEpisode?.chapters?.filter(\.includeInTableOfContents)
    }

    // MARK: - Download badge

    @ViewBuilder
    private var downloadBadge: some View {
        if let id = state.episode?.id,
           let resolved = store.episode(id: id) ?? state.episode {
            DownloadProgressBadge(
                episode: resolved,
                liveProgress: downloadService.progress[id]
            )
        }
    }

    // MARK: - Playback chrome (waveform + transport + actions)

    private var playbackChrome: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            PlayerPrerollSkipButton(state: state, episode: liveEpisode)
                .animation(AppTheme.Animation.spring, value: state.currentTime)
            PlayerScrubberView(state: state, isScrubbing: $isScrubbing)
            PlayerControlsView(
                state: state,
                glassNamespace: glassNamespace,
                chapters: navigableChapters ?? []
            )
            PlayerActionClusterView(
                state: state,
                showSpeedSheet: $showSpeedSheet
            )
        }
    }
}
