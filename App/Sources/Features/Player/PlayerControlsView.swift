import SwiftUI

/// Primary transport row — skip-back / play-pause / skip-forward.
///
/// Designed to be reusable inside the full-screen `PlayerView` and
/// (eventually) inside a CarPlay reflection. Buttons share `glassEffectID`s so
/// callers can wrap them in a `GlassEffectContainer` to get the morph-on-press
/// behaviour described in UX-01 §5.
///
/// **Chapter shortcuts.** Long-press on either skip button jumps to the
/// next/previous chapter when the episode exposes navigable ones — same
/// gesture iOS Music uses for previous/next track. Tap remains the
/// configured-seconds skip. `chapters` is supplied by the parent so the live
/// store is the source of truth (chapters can hydrate after playback starts).
struct PlayerControlsView: View {

    @Bindable var state: PlaybackState
    let glassNamespace: Namespace.ID
    /// Navigable chapters for the currently-loaded episode. Pass `[]` when
    /// the episode has none — the long-press hooks become no-ops.
    var chapters: [Episode.Chapter] = []

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            // Honour the user-configured skip intervals from Settings →
            // Playback. Falls back to 15/30 if the engine reports an invalid
            // value so the SF Symbol still resolves.
            let back = state.skipBackwardSeconds
            let forward = state.skipForwardSeconds
            skipButton(
                seconds: -back,
                glyph: skipGlyph(back, forward: false),
                action: { state.skipBackward() },
                chapterAction: chapters.isEmpty ? nil : {
                    Haptics.medium()
                    state.seekToPreviousChapter(in: chapters)
                }
            )

            playPauseButton

            skipButton(
                seconds: forward,
                glyph: skipGlyph(forward, forward: true),
                action: { state.skipForward() },
                chapterAction: chapters.isEmpty ? nil : {
                    Haptics.medium()
                    state.seekToNextChapter(in: chapters)
                }
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// Picks the closest SF Symbol that ships with iOS for the given seconds.
    /// `gobackward.10/15/30/45/60/75/90` and the matching `goforward.*` are
    /// the supported variants; anything else falls back to `gobackward` /
    /// `goforward` (no number).
    private func skipGlyph(_ seconds: Int, forward: Bool) -> String {
        let supported = [10, 15, 30, 45, 60, 75, 90]
        let prefix = forward ? "goforward" : "gobackward"
        guard let match = supported.min(by: { abs($0 - seconds) < abs($1 - seconds) }),
              abs(match - seconds) <= 5 else {
            return prefix
        }
        return "\(prefix).\(match)"
    }

    // MARK: - Subviews

    private var playPauseButton: some View {
        Button {
            state.togglePlayPause()
        } label: {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("player.play", in: glassNamespace)
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
        }
        .buttonStyle(.pressable(scale: 0.94, opacity: 0.9))
    }

    @ViewBuilder
    private func skipButton(
        seconds: Int,
        glyph: String,
        action: @escaping () -> Void,
        chapterAction: (() -> Void)? = nil
    ) -> some View {
        let label = Image(systemName: glyph)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 56, height: 56)
            .glassEffect(.regular.interactive(), in: .circle)
        let baseLabel = seconds < 0 ? "Skip back \(-seconds) seconds" : "Skip forward \(seconds) seconds"
        if let chapterAction {
            // Tap = configured-seconds skip. Long-press = chapter nav.
            // `simultaneousGesture` keeps both gesture paths active without
            // the Button swallowing the long-press.
            Button(action: action) { label }
                .buttonStyle(.pressable)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in chapterAction() }
                )
                .accessibilityLabel(baseLabel)
                .accessibilityAction(named: seconds < 0 ? "Previous chapter" : "Next chapter") {
                    chapterAction()
                }
        } else {
            Button(action: action) { label }
                .buttonStyle(.pressable)
                .accessibilityLabel(baseLabel)
        }
    }
}

// MARK: - Action cluster (speed / sleep / AirPlay / queue / share)

/// The bottom-row "glass action cluster" — secondary actions per UX-01 §3
/// Zone F. Lives in its own view so the main `PlayerView` body stays under
/// the soft line limit.
struct PlayerActionClusterView: View {

    @Bindable var state: PlaybackState
    @Binding var showSpeedSheet: Bool
    @Binding var showSleepSheet: Bool
    @Binding var showQueueSheet: Bool
    @Binding var showShareSheet: Bool

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
                    .font(.footnote.weight(.semibold))
                Text(label)
                    .font(AppTheme.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}
