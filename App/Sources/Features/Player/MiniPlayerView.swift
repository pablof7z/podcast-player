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

    private var showName: String {
        guard let subID = state.episode?.subscriptionID,
              let sub = store.subscription(id: subID) else { return "" }
        return sub.title
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
        Button(action: onTap) {
            VStack(spacing: 0) {
                content
                progressLine
            }
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Corner.lg))
            .glassEffectID("player.surface", in: glassNamespace)
        }
        .buttonStyle(.pressable(scale: 0.985, opacity: 0.92))
    }

    // MARK: - Inline (compact) layout

    /// The collapsed pill that sits inline with the tab bar. No surrounding
    /// glass surface — the toolbar's own glass shell hosts it.
    private var inlineBody: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.xs) {
                inlineArtwork
                    .glassEffectID("player.artwork", in: glassNamespace)

                Spacer(minLength: 0)

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
        }
        .buttonStyle(.pressable(scale: 0.97, opacity: 0.9))
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
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * progressFraction)
                    .animation(.linear(duration: 0.15), value: state.currentTime)
            }
        }
        .frame(height: 2)
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

    private var metadataLine: some View {
        HStack(spacing: 6) {
            if state.episode != nil {
                if !showName.isEmpty {
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
        return showName.isEmpty ? title : "\(title), \(showName)"
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
