import SwiftUI

/// Full-screen Now Playing surface.
///
/// Layered top-down: hero artwork placeholder → editorial metadata →
/// chapters (with transcript fallback when no chapters exist) → semantic
/// waveform → primary transport → action cluster. All colors and fonts use
/// semantic / Dynamic Type styles so the surface adapts to the user's
/// appearance settings and accent color.
struct PlayerView: View {

    @Environment(AppStateStore.self) private var store
    @Bindable var state: PlaybackState
    @Environment(\.dismiss) private var dismiss
    let glassNamespace: Namespace.ID

    @State private var isScrubbing: Bool = false
    @State private var showSpeedSheet: Bool = false
    @State private var showSleepSheet: Bool = false
    @State private var showQueueSheet: Bool = false
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
                    heroArtwork
                    editorialHeader
                    secondarySurface
                        .frame(minHeight: 240, maxHeight: 320)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            }

            playbackChrome
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.md)
        }
        .sheet(isPresented: $showSpeedSheet) { PlayerSpeedSheet(state: state) }
        .sheet(isPresented: $showSleepSheet) { PlayerSleepTimerSheet(state: state) }
        .sheet(isPresented: $showQueueSheet) {
            PlayerQueueSheet(state: state)
        }
        .sheet(isPresented: $showShareSheet) {
            if let episode = state.episode {
                PlayerShareSheet(state: state, episode: episode, showName: showName)
            }
        }
        .task(id: state.episode?.id) {
            // Best-effort hydrate Podcasting 2.0 chapters JSON when the
            // current episode references one. Idempotent per-URL across
            // the session, so re-opening the player is free.
            if let episode = state.episode {
                ChaptersHydrationService.shared.hydrateIfNeeded(
                    episode: episode,
                    store: store
                )
            }
            // Idempotent — wires the singleton's MPRemoteCommand once and
            // refreshes its playback/store handles every time the episode
            // changes so the snip path always sees live state.
            AutoSnipController.shared.attach(playback: state, store: store)
        }
        .overlay(alignment: .top) {
            AutoSnipBanner(controller: AutoSnipController.shared)
                .padding(.top, AppTheme.Spacing.lg)
                .allowsHitTesting(true)
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
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Minimize player")

            Spacer()

            Text("NOW PLAYING")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            Spacer()

            if let episode = state.episode {
                PlayerMoreMenu(
                    episode: episode,
                    subscription: subscription,
                    onMarkPlayed: { store.markEpisodePlayed(episode.id) },
                    onMarkUnplayed: { store.markEpisodeUnplayed(episode.id) },
                    onDismissPlayer: { dismiss() }
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Hero artwork

    /// Resolved artwork URL with per-chapter override. Priority:
    ///
    ///   1. Active chapter's `imageURL` (Podcasting 2.0 chapters often
    ///      ship topic-aligned imagery — e.g. a guest photo for an
    ///      interview segment). This swaps mid-playback as the chapter
    ///      changes and is the user-visible payoff for chapter hydration.
    ///   2. Per-episode artwork (`<itunes:image>` override).
    ///   3. Show-level cover art via `PlaybackState.resolveShowImage`.
    private var artworkURL: URL? {
        guard let episode = state.episode else { return nil }
        if let chapterImage = activeChapterImageURL { return chapterImage }
        return episode.imageURL ?? state.resolveShowImage(episode)
    }

    /// Active chapter's `img` URL, or `nil` when the active chapter has
    /// none (or the episode has no navigable chapters at all). Reads from
    /// the live store so chapters hydrated after playback started — via
    /// `ChaptersHydrationService` — still produce per-chapter art.
    private var activeChapterImageURL: URL? {
        guard let chapters = navigableChapters, !chapters.isEmpty else { return nil }
        return chapters.active(at: state.currentTime)?.imageURL
    }

    /// Square hero cover art. `AsyncImage` distinguishes loading (neutral
    /// surface, no glyph) from failure (neutral surface + subtle waveform
    /// glyph) so the user never reads the loading state as "no artwork".
    /// The image is keyed on `artworkURL` so a chapter-image swap mid-
    /// playback fades through opacity instead of snapping.
    private var heroArtwork: some View {
        ZStack {
            if let url = artworkURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        artworkFailureFallback
                    case .empty:
                        artworkLoadingPlaceholder
                    @unknown default:
                        artworkLoadingPlaceholder
                    }
                }
                .id(url)
                .transition(.opacity)
            } else {
                artworkFailureFallback
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.xl, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .scaleEffect(isScrubbing ? 0.92 : 1.0)
        .blur(radius: isScrubbing ? 8 : 0)
        .glassEffectID("player.artwork", in: glassNamespace)
        .animation(AppTheme.Animation.spring, value: isScrubbing)
        .animation(.easeInOut(duration: 0.35), value: artworkURL)
        .accessibilityHidden(true)
    }

    /// Neutral surface shown while the artwork is fetching. Intentionally
    /// glyph-free — a placeholder symbol here would read as "no artwork
    /// available" rather than "loading".
    private var artworkLoadingPlaceholder: some View {
        Color.secondary.opacity(0.10)
    }

    /// Neutral surface plus a subtle waveform glyph, shown when artwork
    /// resolution failed (or the episode has no artwork at all) so the hero
    /// area doesn't look broken.
    private var artworkFailureFallback: some View {
        ZStack {
            Color.secondary.opacity(0.10)
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Secondary surface (chapters / transcript)

    /// Player body below the editorial header. Chapters take precedence
    /// when the episode exposes navigable ones — otherwise we fall back to
    /// the transcript scroller so chapter-less episodes don't regress to a
    /// blank box. Clipping/share flows read the transcript directly via
    /// `PlayerShareSheet` regardless of which surface is visible here.
    @ViewBuilder
    private var secondarySurface: some View {
        if let chapters = navigableChapters, !chapters.isEmpty {
            PlayerChaptersScrollView(
                chapters: chapters,
                state: state,
                useGlassCard: true
            )
        } else {
            PlayerTranscriptScrollView(state: state, useGlassCard: true)
        }
    }

    private var navigableChapters: [Episode.Chapter]? {
        // Prefer the live store copy so chapters fetched after the episode
        // entered playback (e.g. async `chaptersURL` JSON hydration) appear
        // without re-opening the player.
        let liveEpisode = state.episode.flatMap { store.episode(id: $0.id) } ?? state.episode
        return liveEpisode?.chapters?.filter(\.includeInTableOfContents)
    }

    // MARK: - Editorial header

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let episode = state.episode {
                if !showName.isEmpty {
                    Text(showName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                }
                Text(episode.title)
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                downloadBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ambient download indicator. Reads through the store so coarse
    /// transitions written by `EpisodeDownloadService` reach the badge
    /// even when `PlaybackState`'s cached `episode` snapshot is stale.
    /// Hidden for `.notDownloaded` via the badge itself.
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
            PlayerScrubberView(state: state, isScrubbing: $isScrubbing)
            PlayerControlsView(
                state: state,
                glassNamespace: glassNamespace,
                chapters: navigableChapters ?? []
            )
            PlayerActionClusterView(
                state: state,
                showSpeedSheet: $showSpeedSheet,
                showSleepSheet: $showSleepSheet,
                showQueueSheet: $showQueueSheet,
                showShareSheet: $showShareSheet
            )
        }
    }
}
