import SwiftUI

// MARK: - HomeContinueListeningCard

/// One card in the Home tab's "Continue listening" hero rail.
///
/// Shows artwork, episode title, show name, and a thin progress bar driven by
/// `episode.playbackPosition / episode.duration`. Tapping the card resumes
/// playback via the env-injected playback state.
struct HomeContinueListeningCard: View {
    let episode: Episode
    let subscription: PodcastSubscription?
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                artwork
                meta
                progress
            }
            .frame(width: 200)
            .padding(AppTheme.Spacing.sm)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Subviews

    private var artworkURL: URL? {
        episode.imageURL ?? subscription?.imageURL
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let url = artworkURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 184, height: 184)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .strokeBorder(AppTheme.Tint.hairline, lineWidth: 0.5)
        )
    }

    private var artworkPlaceholder: some View {
        Image(systemName: "waveform")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(.secondary)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(episode.title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let showName = subscription?.title, !showName.isEmpty {
                Text(showName)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .tint(AppTheme.Tint.agentSurface)
            Text(remainingLabel)
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var progressFraction: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        let raw = episode.playbackPosition / duration
        return max(0, min(1, raw))
    }

    private var remainingLabel: String {
        guard let duration = episode.duration, duration > 0 else {
            return "Resume"
        }
        let remaining = max(0, duration - episode.playbackPosition)
        return "\(formatDuration(remaining)) left"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m) min" }
        return "<1 min"
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let showName = subscription?.title, !showName.isEmpty {
            parts.append(showName)
        }
        parts.append(episode.title)
        let percent = Int((progressFraction * 100).rounded())
        if percent > 0 { parts.append("\(percent) percent listened") }
        parts.append("Tap to resume")
        return parts.joined(separator: ", ")
    }
}
