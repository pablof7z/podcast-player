import SwiftUI

// MARK: - PlayerScrubberView

/// Waveform scrubber + clock readout used by the full-screen `PlayerView`.
///
/// Holds its own scrubbing-gesture state so the parent `PlayerView` doesn't
/// have to plumb `isScrubbing` / `scrubTime` through every subview. The
/// `isScrubbing` value is exposed via a binding so the parent can react
/// (e.g. shrinking the hero artwork while the user drags).
struct PlayerScrubberView: View {

    @Bindable var state: PlaybackState
    @Binding var isScrubbing: Bool

    @State private var scrubTime: TimeInterval = 0
    @State private var waveformWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            PlayerWaveformView(
                duration: state.duration,
                currentTime: isScrubbing ? scrubTime : state.currentTime,
                isScrubbing: isScrubbing
            )
            .frame(height: isScrubbing ? 220 : 56)
            .animation(AppTheme.Animation.spring, value: isScrubbing)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { waveformWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            waveformWidth = newWidth
                        }
                }
            )
            .gesture(scrubGesture)
            .accessibilityElement()
            .accessibilityLabel("Playback scrubber")
            .accessibilityValue(PlayerTimeFormat.progress(state.currentTime, state.duration))
            .accessibilityHint("Swipe up or down to skip")
            .accessibilityAdjustableAction { direction in
                // Honour the user's configured skip intervals — was previously
                // hardcoded to 15 s, ignoring the same value the on-screen
                // skip buttons (and lock-screen) used.
                switch direction {
                case .increment: state.skipForward()
                case .decrement: state.skipBackward()
                @unknown default: break
                }
            }

            HStack {
                Text(PlayerTimeFormat.clock(isScrubbing ? scrubTime : state.currentTime))
                Spacer()
                Text(PlayerTimeFormat.clock(state.duration))
            }
            .font(AppTheme.Typography.monoCaption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    /// Absolute-position scrub: x = 0 maps to 0 s, x = width maps to
    /// `duration`. The previous implementation translated relative finger
    /// motion at `0.4 × duration / width` — so a 3-hour episode required
    /// roughly seven full-width swipes to traverse end-to-end.
    ///
    /// `minimumDistance: 4` suppresses the visual scrub-flash from
    /// incidental taps; the previous `0` value triggered the 56→220 pt
    /// expansion + hero blur on every brush.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let width = waveformWidth
                guard width > 0 else { return }
                if !isScrubbing {
                    isScrubbing = true
                    scrubTime = state.currentTime
                    Haptics.soft()
                }
                let fraction = max(0, min(1, value.location.x / width))
                scrubTime = state.duration * Double(fraction)
            }
            .onEnded { _ in
                if isScrubbing {
                    state.seekSnapping(to: scrubTime)
                    Haptics.medium()
                }
                isScrubbing = false
            }
    }
}
