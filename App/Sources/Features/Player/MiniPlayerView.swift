import SwiftUI

/// Persistent mini-player docked above the tab bar.
///
/// **Signature behaviour (UX-01 §6.5):** the ticker line is the **active
/// transcript line**, not just the episode title. That single decision is what
/// separates this player from every other one on the App Store — the user
/// always knows what's *being said* without opening the full surface.
struct MiniPlayerView: View {

    @Bindable var state: MockPlaybackState
    let onTap: () -> Void
    let glassNamespace: Namespace.ID

    private var copperAccent: Color { state.episode?.primaryArtColor ?? .orange }

    var body: some View {
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
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.xs)
        }
        .buttonStyle(.pressable(scale: 0.985, opacity: 0.92))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
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
