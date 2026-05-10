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
            SkipButton(
                seconds: back,
                direction: .backward,
                tapAction: { state.skipBackward() },
                chapterAction: chapters.isEmpty ? nil : { state.seekToPreviousChapter(in: chapters) }
            )

            playPauseButton

            SkipButton(
                seconds: forward,
                direction: .forward,
                tapAction: { state.skipForward() },
                chapterAction: chapters.isEmpty ? nil : { state.seekToNextChapter(in: chapters) }
            )
        }
        .frame(maxWidth: .infinity)
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
}

// MARK: - SkipButton

/// Tap = configured-seconds skip; long-press = chapter nav (when chapters
/// available). `simultaneousGesture` previously fired BOTH actions because
/// it doesn't suppress the Button's tap on release — this struct guards
/// the tap with a `didLongPress` flag so a long-press is exclusive.
///
/// The SF Symbol picker requires an exact match so the visible number
/// always equals the configured interval. A user with a 20 s skip used to
/// see `goforward.15` (closest stocked variant ±5 s) but the action
/// skipped 20 s — the visible label silently lied. Anything off-grid now
/// falls back to bare `goforward`/`gobackward` (no digit) so the visual
/// stays honest.
private struct SkipButton: View {

    enum Direction { case forward, backward }

    let seconds: Int
    let direction: Direction
    let tapAction: () -> Void
    let chapterAction: (() -> Void)?

    @State private var didLongPress = false

    var body: some View {
        let label = Image(systemName: glyph)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 56, height: 56)
            .glassEffect(.regular.interactive(), in: .circle)

        let baseLabel: String = direction == .backward
            ? "Skip back \(seconds) seconds"
            : "Skip forward \(seconds) seconds"

        Button {
            if didLongPress {
                didLongPress = false
                return
            }
            tapAction()
        } label: { label }
        .buttonStyle(.pressable)
        .modifier(LongPressChapterModifier(
            chapterAction: chapterAction,
            didLongPress: $didLongPress
        ))
        .accessibilityLabel(baseLabel)
        .modifier(ChapterAccessibilityActionModifier(
            direction: direction,
            chapterAction: chapterAction
        ))
    }

    private var glyph: String {
        let supported = [10, 15, 30, 45, 60, 75, 90]
        let prefix = direction == .forward ? "goforward" : "gobackward"
        // Exact match only — see comment above on why.
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

private struct LongPressChapterModifier: ViewModifier {
    let chapterAction: (() -> Void)?
    @Binding var didLongPress: Bool

    func body(content: Content) -> some View {
        if let chapterAction {
            content.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        didLongPress = true
                        Haptics.heavy()
                        chapterAction()
                    }
            )
        } else {
            content
        }
    }
}

private struct ChapterAccessibilityActionModifier: ViewModifier {
    let direction: SkipButton.Direction
    let chapterAction: (() -> Void)?

    func body(content: Content) -> some View {
        if let chapterAction {
            content.accessibilityAction(named: direction == .backward ? "Previous chapter" : "Next chapter") {
                chapterAction()
            }
        } else {
            content
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
            actionChip(
                label: state.rate.label,
                glyph: "speedometer",
                accessibilityName: "Playback speed",
                accessibilityValue: state.rate.label
            ) {
                showSpeedSheet = true
            }
            actionChip(
                label: state.sleepTimerChipLabel,
                glyph: "moon.fill",
                accessibilityName: "Sleep timer",
                accessibilityValue: sleepTimerSpokenValue
            ) {
                showSleepSheet = true
            }
            routePickerChip
            actionChip(
                label: "Up Next",
                glyph: "list.bullet",
                accessibilityName: "Up Next queue"
            ) {
                showQueueSheet = true
            }
            actionChip(
                label: "More",
                glyph: "ellipsis.circle",
                accessibilityName: "Share and copy options"
            ) {
                showShareSheet = true
            }
            AutoSnipButton()
        }
        .frame(maxWidth: .infinity)
    }

    /// VoiceOver-friendly spoken form of the sleep-timer state. The chip's
    /// visible label is just `state.sleepTimerChipLabel` (e.g. "29:42") —
    /// fine for sighted users next to a moon glyph, but a bare time read out
    /// loud is meaningless.
    private var sleepTimerSpokenValue: String {
        switch state.sleepTimer {
        case .off: return "Off"
        case .minutes: return "\(state.sleepTimerChipLabel) remaining"
        case .endOfEpisode: return "Until end of episode"
        }
    }

    /// Output-route chip backed by `AVRoutePickerView`. Tapping presents
    /// the system route picker (AirPlay, Bluetooth, USB-C) — replaces the
    /// previous fake toggle that flipped a `PlaybackState.isAirPlayActive`
    /// bool but never actually changed the audio route.
    private var routePickerChip: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "airplayaudio")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text("Output")
                    .font(AppTheme.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .glassEffect(.regular.interactive(), in: .capsule)
            // Invisible AVRoutePickerView overlaid to capture taps —
            // suppress the OS-drawn glyph (tintColor + activeTintColor =
            // .clear) so only our chip is visible. The picker still
            // presents the system route sheet on tap. Hide the picker
            // from VoiceOver so it doesn't double-announce on top of our
            // own combined label.
            RoutePickerView(activeTintColor: .clear, tintColor: .clear)
                .allowsHitTesting(true)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio output")
        .accessibilityHint("Opens system output picker")
    }

    private func actionChip(
        label: String,
        glyph: String,
        accessibilityName: String,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(AppTheme.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityAddTraits(.isButton)
    }
}
