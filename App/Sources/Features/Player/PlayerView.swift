import SwiftUI

/// Full-screen Now Playing surface.
///
/// Layout: a single vertical `ScrollView` whose content is the compact
/// episode header (artwork left, title/show/metadata right) followed by the
/// chapter rail. The top bar floats with the close button + the
/// share/AirPlay/more cluster, swapping the middle label from show-name to a
/// compact artwork+title once the hero has scrolled offscreen. The playback
/// chrome (scrubber + transport + action cluster) floats at the bottom in a
/// single glass island via `safeAreaInset(edge: .bottom)`. Colors and fonts
/// use semantic / Dynamic Type styles so the surface adapts to the user's
/// appearance settings and accent color.
struct PlayerView: View {

    @Environment(AppStateStore.self) private var store
    @Bindable var state: PlaybackState
    @Environment(\.dismiss) private var dismiss
    let glassNamespace: Namespace.ID

    @State private var isScrubbing: Bool = false
    @State private var showSpeedSheet: Bool = false
    @State private var showSleepSheet: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showVoiceNoteSheet: Bool = false

    /// Vertical scroll offset of the content. Driven by
    /// `.onScrollGeometryChange` rather than a preference key so the
    /// title-swap doesn't ride the layout-pass treadmill.
    @State private var scrollOffset: CGFloat = 0

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

    /// Roughly the height of the hero artwork (110 pt) + a bit of padding —
    /// once the user has scrolled past this, the compact title takes over
    /// the top bar's middle slot.
    private let titleSwapThreshold: CGFloat = 90

    private var titleCollapsed: Bool {
        scrollOffset > titleSwapThreshold
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    episodeHeader
                    chaptersContent
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                scrollOffset = newOffset
            }
            .onAppear {
                // One-time scroll-to-active on open. We intentionally do NOT
                // re-center on chapter changes because the chapter rail now
                // scrolls with the rest of the page — re-centering every
                // boundary crossing would jerk the artwork header.
                guard let activeID = navigableChapters?.active(at: state.currentTime)?.id else { return }
                proxy.scrollTo(activeID, anchor: .center)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { floatingChrome }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PlayerEditorialBackdrop(artworkURL: artworkURL)
        }
        .sheet(isPresented: $showSpeedSheet) { PlayerSpeedSheet(state: state) }
        .sheet(isPresented: $showSleepSheet) { PlayerSleepTimerSheet(state: state) }
        .sheet(isPresented: $showVoiceNoteSheet) {
            VoiceNoteRecordingSheet(state: state)
                .environment(store)
        }
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
            }
            AutoSnipController.shared.attach(playback: state, store: store)
        }
        .overlay(alignment: .top) {
            VStack(spacing: AppTheme.Spacing.sm) {
                AutoSnipBanner(controller: AutoSnipController.shared)
                    .allowsHitTesting(false)
                NoLLMKeyHintBanner(controller: AutoSnipController.shared)
            }
            .padding(.top, AppTheme.Spacing.lg)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        PlayerTopBar(
            state: state,
            subscription: subscription,
            showName: showName,
            artworkURL: artworkURL,
            titleCollapsed: titleCollapsed,
            onDismiss: { dismiss() },
            onShare: { showShareSheet = true },
            onShowSleepTimer: { showSleepSheet = true }
        )
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

    // MARK: - Chapters / placeholder

    @ViewBuilder
    private var chaptersContent: some View {
        if let chapters = navigableChapters, !chapters.isEmpty {
            PlayerChaptersScrollView(
                chapters: chapters,
                state: state
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

    // MARK: - Floating playback chrome (scrubber + transport + actions)

    private var episodeClips: [Clip] {
        guard let id = state.episode?.id else { return [] }
        return store.clips(forEpisode: id)
    }

    /// Pulled out of the scroll body and attached via
    /// `safeAreaInset(edge: .bottom)` so the chapter list scrolls under it.
    /// Wrapped in a `GlassEffectContainer` so the morph-on-press animations
    /// across all the round controls read as one floating island rather
    /// than five disconnected glass coins.
    private var floatingChrome: some View {
        GlassEffectContainer(spacing: AppTheme.Spacing.md) {
            VStack(spacing: AppTheme.Spacing.md) {
                PlayerPrerollSkipButton(state: state, episode: liveEpisode)
                    .animation(AppTheme.Animation.spring, value: state.currentTime)
                PlayerScrubberView(
                    state: state,
                    isScrubbing: $isScrubbing,
                    chapters: navigableChapters ?? [],
                    clips: episodeClips,
                    onClipTap: { clip in state.navigationalSeek(to: clip.startSeconds) }
                )
                PlayerControlsView(
                    state: state,
                    glassNamespace: glassNamespace,
                    chapters: navigableChapters ?? []
                )
                PlayerActionClusterView(
                    state: state,
                    showSpeedSheet: $showSpeedSheet,
                    showVoiceNoteSheet: $showVoiceNoteSheet
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.md)
    }
}
