import SwiftUI

/// Persistent mini-player presented as a `tabViewBottomAccessory` (iOS 26).
///
/// Reads `\.tabViewBottomAccessoryPlacement` from the environment and
/// renders one of two layouts:
///   - `.expanded` — full mini-bar above the tab bar with the episode title.
///   - `.inline`   — compact pill that slots between the active-tab capsule
///     and the trailing toolbar controls when the tab bar collapses on
///     scroll-down (Apple Music pattern).
///
/// The expanded UI shows artwork, the episode title, the show name + clock,
/// and play / +30s. The inline pill drops to artwork + play/pause only.
struct MiniPlayerView: View {

    @Environment(AppStateStore.self) private var store
    @Bindable var state: PlaybackState
    let onTap: () -> Void
    let glassNamespace: Namespace.ID

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// Observed so the inline download badge tracks the service's
    /// `progress[id]` map without each 5%/200ms tick re-rendering through
    /// `AppStateStore`. Mirrors the pattern used by `EpisodeRow`.
    @State private var downloadService = EpisodeDownloadService.shared

    private var showName: String {
        guard let subID = state.episode?.subscriptionID,
              let sub = store.subscription(id: subID) else { return "" }
        return sub.title
    }

    /// Title of the chapter containing the playhead, when the live episode
    /// has navigable chapters. Returns `nil` for chapter-less episodes so
    /// the metadata line falls back to the show name. Reads from
    /// `AppStateStore` rather than the cached `state.episode` so chapters
    /// hydrated by `ChaptersHydrationService` after playback started show
    /// up here without a re-load.
    private var activeChapterTitle: String? {
        guard let stateEpisode = state.episode else { return nil }
        let live = store.episode(id: stateEpisode.id) ?? stateEpisode
        let navigable = live.chapters?.filter(\.includeInTableOfContents) ?? []
        guard !navigable.isEmpty else { return nil }
        return navigable.active(at: state.currentTime)?.title
    }

    var body: some View {
        Group {
            switch placement {
            case .inline:
                inlineBody
            default:
                expandedBody
            }
        }
        .animation(AppTheme.Animation.spring, value: placement)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Expanded (regular) layout

    private var expandedBody: some View {
        // Wrapping in `Button(action: onTap)` collapses every nested Button
        // (Pause, Skip Forward) into the parent's tap target — sighted users
        // tapping the visible pause icon end up *expanding* the player
        // instead of pausing. Worse, the inner Buttons disappear from the
        // accessibility tree as direct AXButtons and reappear as custom
        // actions on the parent (only reachable via the VoiceOver rotor).
        // Use a non-Button tap surface so the nested transport Buttons keep
        // their own gestures, and limit the expand-on-tap target to the
        // non-button regions via `.contentShape` + `.onTapGesture` on the
        // background, not the whole stack.
        //
        // Progress line is an OVERLAY at the top edge — Overcast-style,
        // high-glance, always-visible. Putting it inside the VStack
        // *under* the glassEffect makes the bar disappear into the glass
        // material; lifting it into an overlay renders it crisply on top.
        content
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Corner.lg))
            .glassEffectID("player.surface", in: glassNamespace)
            .overlay(alignment: .top) {
                progressLine
                    .padding(.horizontal, AppTheme.Corner.lg)
            }
            .contentShape(.rect(cornerRadius: AppTheme.Corner.lg))
            .onTapGesture {
                Haptics.light()
                onTap()
            }
            .accessibilityElement(children: .contain)
    }

    // MARK: - Inline (compact) layout

    /// The collapsed pill that sits inline with the tab bar. No surrounding
    /// glass surface — the toolbar's own glass shell hosts it.
    ///
    /// Same Button-inside-Button trap as `expandedBody`: the play/pause icon
    /// has to remain a real, separately-tappable Button. Use a non-Button
    /// tap surface for the expand-on-tap action.
    ///
    /// Title is included alongside the artwork — without it, the pill reads
    /// as a generic glass slab and the underlying scroll content shows
    /// through the translucent background, making it look broken. Apple
    /// Music's pill omits the title because their artwork conveys identity
    /// strongly; podcast covers don't, so we need text.
    private var inlineBody: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            inlineArtwork
                .glassEffectID("player.artwork", in: glassNamespace)

            inlineTitle
                .frame(maxWidth: .infinity, alignment: .leading)

            inlineDownloadBadge

            inlineDownloadBadge

            Button {
                state.togglePlayPause()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .glassEffectID("player.play", in: glassNamespace)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            onTap()
        }
    }

    /// Inline-only download surface — narrow visibility rule per spec:
    /// only render when the live episode is actively downloading or has
    /// failed. The collapsed pill has no horizontal slack for `.queued`
    /// or terminal `.downloaded` states, and they'd add visual noise to
    /// the tab bar without informing an in-flight action.
    @ViewBuilder
    private var inlineDownloadBadge: some View {
        if let resolved = liveDownloadEpisode {
            switch resolved.downloadState {
            case .downloading(let persistedProgress, _):
                let live = downloadService.progress[resolved.id] ?? persistedProgress
                let pct = Int((max(0, min(1, live)) * 100).rounded())
                Text("\(pct)%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Downloading \(pct) percent")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Download failed")
            default:
                EmptyView()
            }
        }
    }

    /// Re-resolves `state.episode` through the store so coarse download
    /// transitions (`.downloading → .downloaded`) reach the badge without
    /// requiring `PlaybackState` to refresh its cached snapshot.
    private var liveDownloadEpisode: Episode? {
        guard let id = state.episode?.id else { return nil }
        return store.episode(id: id) ?? state.episode
    }

    @ViewBuilder
    private var inlineTitle: some View {
        if let episode = state.episode {
            Text(episode.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Inline-only download surface — narrow visibility rule per spec:
    /// only render when the live episode is actively downloading or has
    /// failed. The collapsed pill has no horizontal slack for `.queued`
    /// or terminal `.downloaded` states, and they'd add visual noise to
    /// the tab bar without informing an in-flight action.
    @ViewBuilder
    private var inlineDownloadBadge: some View {
        if let resolved = liveDownloadEpisode {
            switch resolved.downloadState {
            case .downloading, .failed:
                DownloadProgressBadge(
                    episode: resolved,
                    liveProgress: downloadService.progress[resolved.id]
                )
            default:
                EmptyView()
            }
        }
    }

    private var inlineArtwork: some View {
        artworkSurface(
            size: 26,
            cornerRadius: AppTheme.Corner.sm,
            placeholderGlyphSize: 11
        )
    }

    // MARK: - Subviews

    private var progressLine: some View {
        // 3px is the readable minimum on top of a glass material — 2px
        // disappears against the translucent backdrop. Background uses
        // `Color.accentColor.opacity(0.20)` so the unfilled segment also
        // tints toward the accent and the bar reads as a meter even before
        // the playhead has moved.
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.20))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * progressFraction)
                    .animation(.linear(duration: 0.15), value: state.currentTime)
            }
        }
        .frame(height: 3)
    }

    private var content: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            artwork
                .glassEffectID("player.artwork", in: glassNamespace)

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                metadataLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            transportButtons
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var artwork: some View {
        artworkSurface(
            size: 44,
            cornerRadius: AppTheme.Corner.md,
            placeholderGlyphSize: 18
        )
    }

    /// Resolved artwork URL — episode override first, then the show-level
    /// fallback via `PlaybackState.resolveShowImage` (the same closure the
    /// full Player uses, wired in `RootView`).
    private var artworkURL: URL? {
        guard let episode = state.episode else { return nil }
        return episode.imageURL ?? state.resolveShowImage(episode)
    }

    /// Shared artwork rendering for both the expanded (44pt) and inline
    /// (26pt) layouts. Loading state is glyph-free so the user doesn't read
    /// it as "no artwork"; failure state shows a subtle waveform indicator.
    @ViewBuilder
    private func artworkSurface(
        size: CGFloat,
        cornerRadius: CGFloat,
        placeholderGlyphSize: CGFloat
    ) -> some View {
        ZStack {
            if let url = artworkURL {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 64, height: 64)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        miniArtworkFailureFallback(glyphSize: placeholderGlyphSize)
                    case .empty:
                        Color.secondary.opacity(0.18)
                    @unknown default:
                        Color.secondary.opacity(0.18)
                    }
                }
            } else {
                miniArtworkFailureFallback(glyphSize: placeholderGlyphSize)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func miniArtworkFailureFallback(glyphSize: CGFloat) -> some View {
        ZStack {
            Color.secondary.opacity(0.18)
            Image(systemName: "waveform")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var titleLine: some View {
        if let episode = state.episode {
            Text(episode.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        if state.episode != nil {
            HStack(spacing: 6) {
                if let chapterTitle = activeChapterTitle {
                    Image(systemName: "book.pages")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(chapterTitle)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(.opacity)
                        .id(chapterTitle)
                    Text("·")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.tertiary)
                } else if !showName.isEmpty {
                    Text(showName)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(PlayerTimeFormat.clock(state.currentTime))
                    .font(AppTheme.Typography.mono)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .animation(AppTheme.Animation.spring, value: activeChapterTitle)
        }
    }

    private var transportButtons: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Button {
                state.togglePlayPause()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .glassEffectID("player.play", in: glassNamespace)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

            Button {
                state.skipForward()
            } label: {
                Image(systemName: forwardSkipGlyph)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Skip forward \(state.skipForwardSeconds) seconds")
        }
    }

    private var progressFraction: CGFloat {
        guard state.duration > 0 else { return 0 }
        return CGFloat(state.currentTime / state.duration)
    }

    private var accessibilityLabel: String {
        let title = state.episode?.title ?? "Now playing"
        var parts: [String] = [title]
        if let chapter = activeChapterTitle {
            parts.append("Chapter: \(chapter)")
        } else if !showName.isEmpty {
            parts.append(showName)
        }
        return parts.joined(separator: ", ")
    }

    /// Picks the closest SF Symbol to the user's configured skip-forward
    /// interval. iOS only ships a numeric variant for {10, 15, 30, 45, 60, 75, 90}.
    private var forwardSkipGlyph: String {
        let supported = [10, 15, 30, 45, 60, 75, 90]
        let seconds = state.skipForwardSeconds
        guard let match = supported.min(by: { abs($0 - seconds) < abs($1 - seconds) }),
              abs(match - seconds) <= 5 else {
            return "goforward"
        }
        return "goforward.\(match)"
    }
}
