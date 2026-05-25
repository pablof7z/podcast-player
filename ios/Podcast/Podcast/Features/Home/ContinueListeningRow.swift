import SwiftUI

// MARK: - ContinueListeningRow

/// One compact row in the Home "Continue Listening" section.
///
/// Until `EpisodeSummary` projects `position_secs` (PR #56), per-episode
/// resume points are only available for the *active* episode via
/// `PlayerState`. Once the field lands, this row will be reused for
/// per-episode resume rows from the library. Tap routing happens in
/// the enclosing `HomeView`.
struct ContinueListeningRow: View {

    let episode: EpisodeSummary
    let podcast: PodcastSummary
    /// Resume position in seconds (typically `PlayerState.positionSecs`).
    let positionSecs: Double
    /// Episode duration in seconds when known.
    let durationSecs: Double?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            artworkTile.frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(podcast.title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                progressBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .fill(.background.secondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(episode.title), \(podcast.title), \(Int(progressFraction * 100)) percent played")
    }

    @ViewBuilder
    private var artworkTile: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
        Group {
            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(shape)
    }

    private var placeholder: some View {
        ZStack {
            Color.accentColor.opacity(0.25)
            Image(systemName: "headphones")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var artworkURL: URL? {
        if let s = episode.artworkUrl, let url = URL(string: s) { return url }
        if let s = podcast.artworkUrl, let url = URL(string: s) { return url }
        return nil
    }

    private var progressFraction: Double {
        guard let total = durationSecs, total > 0 else { return 0 }
        return min(max(positionSecs / total, 0), 1)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * progressFraction)
            }
        }
        .frame(height: 3)
    }
}
