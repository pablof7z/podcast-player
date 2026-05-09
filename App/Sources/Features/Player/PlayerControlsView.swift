import SwiftUI

/// Primary transport row — skip-back / play-pause / skip-forward.
///
/// Designed to be reusable inside the full-screen `PlayerView` and
/// (eventually) inside a CarPlay reflection. Buttons share `glassEffectID`s so
/// callers can wrap them in a `GlassEffectContainer` to get the morph-on-press
/// behaviour described in UX-01 §5.
struct PlayerControlsView: View {

    @Bindable var state: MockPlaybackState
    let copperAccent: Color
    let glassNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            skipButton(seconds: -15, glyph: "gobackward.15") {
                state.skipBackward(15)
            }

            playPauseButton

            skipButton(seconds: 30, glyph: "goforward.30") {
                state.skipForward(30)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Subviews

    private var playPauseButton: some View {
        Button {
            state.togglePlayPause()
        } label: {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .glassEffect(
                    .regular.tint(copperAccent.opacity(0.55)).interactive(),
                    in: .circle
                )
                .glassEffectID("player.play", in: glassNamespace)
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
        }
        .buttonStyle(.pressable(scale: 0.94, opacity: 0.9))
    }

    private func skipButton(seconds: Int, glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: glyph)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 56, height: 56)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(seconds < 0 ? "Skip back \(-seconds) seconds" : "Skip forward \(seconds) seconds")
    }
}

// MARK: - Action cluster (speed / sleep / AirPlay / queue / share)

/// The bottom-row "glass action cluster" — secondary actions per UX-01 §3
/// Zone F. Lives in its own view so the main `PlayerView` body stays under
/// the soft line limit.
struct PlayerActionClusterView: View {

    @Bindable var state: MockPlaybackState
    @Binding var showSpeedSheet: Bool
    @Binding var showSleepSheet: Bool
    @Binding var showQueueSheet: Bool
    @Binding var showShareSheet: Bool
    let copperAccent: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            actionChip(label: state.rate.label, glyph: "speedometer") {
                showSpeedSheet = true
            }
            actionChip(
                label: state.sleepTimer == .off ? "Sleep" : state.sleepTimer.label,
                glyph: "moon.fill"
            ) {
                showSleepSheet = true
            }
            actionChip(
                label: state.isAirPlayActive ? "AirPlay" : "Output",
                glyph: "airplayaudio"
            ) {
                state.isAirPlayActive.toggle()
                Haptics.selection()
            }
            actionChip(label: "Queue", glyph: "list.bullet") {
                showQueueSheet = true
            }
            actionChip(label: "Share", glyph: "square.and.arrow.up") {
                showShareSheet = true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionChip(label: String, glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(AppTheme.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}
