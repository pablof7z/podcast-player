import SwiftUI

/// Persistent mini-player presented as a `tabViewBottomAccessory` (iOS 26).
///
/// Reads `\.tabViewBottomAccessoryPlacement` from the environment and
/// renders one of two layouts:
///   - `.expanded` — full mini-bar above the tab bar with the active
///     transcript line as the ticker (the UX-01 §6.5 signature).
///   - `.inline`   — compact pill that slots between the active-tab capsule
///     and the trailing toolbar controls when the tab bar collapses on
///     scroll-down (Apple Music pattern).
///
/// The full UI shows artwork, the live transcript ticker line, the show name
/// + clock, and play / +30s. The inline pill drops to artwork + play/pause
/// only — no ticker, no progress, no metadata.
struct MiniPlayerView: View {

    @Bindable var state: MockPlaybackState
    let onTap: () -> Void
    let glassNamespace: Namespace.ID

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var copperAccent: Color { state.episode?.primaryArtColor ?? .orange }

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
                progressLine
                content
            }
            .glassEffect(
                .regular.tint(copperAccent.opacity(0.18)),
                in: .rect(cornerRadius: AppTheme.Corner.lg)
            )
            .glassEffectID("player.surface", in: glassNamespace)
        }
        .buttonStyle(.pressable(scale: 0.985, opacity: 0.92))
    }

    // MARK: - Inline (compact) layout

    /// The collapsed pill that sits inline with the tab bar. No surrounding
    /// glass surface — the toolbar's own glass shell hosts it. Just artwork,
    /// the active speaker dot, and a play/pause button.
    private var inlineBody: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.xs) {
                inlineArtwork
                    .glassEffectID("player.artwork", in: glassNamespace)

                if let active = state.activeLine {
                    Circle()
                        .fill(active.speakerColor)
                        .frame(width: 5, height: 5)
                }

                Spacer(minLength: 0)

                Button {
                    state.togglePlayPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
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
        ZStack {
            LinearGradient(
                colors: [
                    state.episode?.primaryArtColor ?? .orange,
                    state.episode?.secondaryArtColor ?? .indigo
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Subviews

    private var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                Rectangle()
                    .fill(copperAccent)
                    .frame(width: proxy.size.width * progressFraction)
                    .animation(.linear(duration: 0.15), value: state.currentTime)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.top, AppTheme.Spacing.xs)
    }

    private var content: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            artwork
                .glassEffectID("player.artwork", in: glassNamespace)

            VStack(alignment: .leading, spacing: 2) {
                tickerLine
                metadataLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            transportButtons
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var artwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    state.episode?.primaryArtColor ?? .orange,
                    state.episode?.secondaryArtColor ?? .indigo
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// **The signature.** The active transcript line, ticker-style. Falls back
    /// to the episode title only if the transcript is empty.
    private var tickerLine: some View {
        Group {
            if let active = state.activeLine {
                HStack(spacing: 6) {
                    Circle()
                        .fill(active.speakerColor)
                        .frame(width: 5, height: 5)
                    Text(active.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id(active.id) // re-renders → matchedGeometry-friendly fade
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .animation(AppTheme.Animation.spring, value: active.id)
            } else if let episode = state.episode {
                Text(episode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 6) {
            if let episode = state.episode {
                Text(episode.showName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.white.opacity(0.35))
                Text(PlayerTimeFormat.clock(state.currentTime))
                    .font(.system(size: 11, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffectID("player.play", in: glassNamespace)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

            Button {
                state.skipForward(30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Skip forward 30 seconds")
        }
    }

    private var progressFraction: CGFloat {
        guard state.duration > 0 else { return 0 }
        return CGFloat(state.currentTime / state.duration)
    }

    private var accessibilityLabel: String {
        let title = state.episode?.title ?? "Now playing"
        let active = state.activeLine.map { "\($0.speakerName) said: \($0.text)" } ?? ""
        return [title, active].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
