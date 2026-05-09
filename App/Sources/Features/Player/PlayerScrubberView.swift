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
    @State private var waveformWidth: CGFloat = 320

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
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: state.skipForward(15)
                case .decrement: state.skipBackward(15)
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

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isScrubbing {
                    isScrubbing = true
                    scrubTime = state.currentTime
                    Haptics.soft()
                }
                let width = max(waveformWidth, 1)
                let dx = value.translation.width / width
                let delta = TimeInterval(dx) * state.duration * 0.4
                scrubTime = max(0, min(state.currentTime + delta, state.duration))
            }
            .onEnded { _ in
                state.seekSnapping(to: scrubTime)
                isScrubbing = false
            }
    }
}
