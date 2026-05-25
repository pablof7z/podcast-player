import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

// MARK: - PodcastLiveActivityWidget
//
// `ActivityConfiguration` is the WidgetKit entry point for an ActivityKit
// activity. The system calls the configuration's view builders whenever
// the app pushes a new `ContentState`; the layouts below render the
// activity on every surface where iOS displays it.
//
// Surfaces:
//   - Lock screen / banner: full `lockScreen` view (artwork + titles + bar)
//   - Dynamic Island compact: leading + trailing badges
//   - Dynamic Island minimal: single play/pause glyph
//   - Dynamic Island expanded: three-region layout (leading artwork,
//     trailing remaining-time, bottom progress bar + title)
//
// All views read from `context.state` (mutable per-update payload) and
// `context.attributes` (immutable per-activity payload — only the
// episode id today). Nothing here touches the App Group; the activity
// is its own data channel, kept in lock-step by `LiveActivityManager`.

@available(iOS 16.2, *)
struct PodcastLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PodcastActivityAttributes.self) { context in
            // Lock screen + banner presentation.
            PodcastLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Color(white: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PodcastLiveActivityArtwork(url: context.state.artworkURL, size: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formattedRemaining(state: context.state))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.episodeTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.podcastTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.positionFraction)
                        .progressViewStyle(.linear)
                        .tint(.white)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(formattedRemaining(state: context.state))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
                    .foregroundStyle(.white)
            }
            .keylineTint(.white)
        }
    }
}

// MARK: - Lock-screen presentation

/// Two-column layout: artwork on the leading edge, title/show/progress
/// on the trailing column. Mirrors the structure of the existing
/// home-screen widget so the visual language is consistent across
/// every now-playing surface.
@available(iOS 16.2, *)
struct PodcastLiveActivityLockScreenView: View {
    let state: PodcastActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PodcastLiveActivityArtwork(url: state.artworkURL, size: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.episodeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(state.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Spacer(minLength: 0)

                ProgressView(value: state.positionFraction)
                    .progressViewStyle(.linear)
                    .tint(.white)

                HStack(spacing: 6) {
                    Image(systemName: state.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formattedRemaining(state: state))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Artwork

/// Async-loaded artwork with a brand placeholder. Sized via the
/// `size` parameter so the same view can render at the lock-screen
/// scale (56pt) and the Dynamic Island expanded scale (44pt).
@available(iOS 16.2, *)
struct PodcastLiveActivityArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            Image(systemName: "waveform")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Formatting helpers

/// Render the remaining time as `−MM:SS` (or `−H:MM:SS` for long
/// episodes). Returns an empty string for unknown / zero-duration
/// content so the Dynamic Island layout collapses cleanly instead of
/// showing a misleading `−0:00`.
@available(iOS 16.2, *)
private func formattedRemaining(state: PodcastActivityAttributes.ContentState) -> String {
    guard state.durationSecs > 0 else { return "" }
    let remaining = max(0, state.durationSecs - state.positionSecs)
    let formatter = remainingFormatter
    return "−" + (formatter.string(from: remaining) ?? "")
}

private let remainingFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.hour, .minute, .second]
    f.unitsStyle = .positional
    f.zeroFormattingBehavior = [.pad]
    return f
}()

#endif
