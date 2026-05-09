import SwiftUI

// MARK: - HomeEpisodeRoute

/// Navigation value pushed onto Home's `NavigationStack` when the user picks
/// "Episode details" from a row's context menu. Home owns its own route value
/// (rather than reusing Library's) to keep the feature boundary clean —
/// `EpisodeDetailView` resolves the episode from `AppStateStore` via `episodeID`.
struct HomeEpisodeRoute: Hashable {
    let episodeID: UUID
}

// MARK: - HomeRecentEpisodeRow

/// One row in the Home tab's "New episodes" feed.
///
/// Shows artwork, show name, episode title, relative pub date, and duration.
/// Tap plays the episode; long-press exposes "Mark as played" and an
/// "Episode details" navigation hop.
struct HomeRecentEpisodeRow: View {
    let episode: Episode
    let subscription: PodcastSubscription?
    let onPlay: () -> Void
    let onMarkPlayed: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                artwork
                meta
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, AppTheme.Spacing.xs)
        .contextMenu(
            menuItems: {
                Button {
                    onMarkPlayed()
                } label: {
                    Label("Mark as played", systemImage: "checkmark.circle")
                }
                NavigationLink(value: HomeEpisodeRoute(episodeID: episode.id)) {
                    Label("Episode details", systemImage: "info.circle")
                }
            },
            preview: {
                HomeEpisodePreviewCard(
                    episode: episode,
                    subscription: subscription,
                    relativePublished: relativePublished,
                    durationLabel: durationLabel
                )
            }
        )
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
                CachedAsyncImage(url: url, targetSize: CGSize(width: 56, height: 56)) { phase in
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
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
                .strokeBorder(AppTheme.Tint.hairline, lineWidth: 0.5)
        )
    }

    private var artworkPlaceholder: some View {
        Image(systemName: "waveform")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(.secondary)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let showName = subscription?.title, !showName.isEmpty {
                Text(showName)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(episode.title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            metaRow
        }
    }

    private var metaRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(relativePublished)
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(.secondary)
            if let durationLabel {
                Text("·")
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.tertiary)
                Text(durationLabel)
                    .font(AppTheme.Typography.mono)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var relativePublished: String {
        Self.relativeFormatter.localizedString(for: episode.pubDate, relativeTo: Date())
    }

    private var durationLabel: String? {
        guard let duration = episode.duration, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m) min" }
        return "<1 min"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let showName = subscription?.title, !showName.isEmpty {
            parts.append(showName)
        }
        parts.append(episode.title)
        parts.append(relativePublished)
        if let durationLabel {
            parts.append(durationLabel)
        }
        parts.append("Tap to play")
        return parts.joined(separator: ", ")
    }
}

// MARK: - HomeEpisodePreviewCard

/// Lifted artwork-hero card shown as the `.contextMenu(preview:)` for a
/// recent-episode row. Layout: square artwork on top (show or episode art,
/// with a tasteful symbol fallback) and a postcard-style metadata block
/// below — show name in tracked small-caps, episode title in serif, and
/// the same `relativePublished` / `durationLabel` strings the row computes.
private struct HomeEpisodePreviewCard: View {
    let episode: Episode
    let subscription: PodcastSubscription?
    let relativePublished: String
    let durationLabel: String?

    private static let previewWidth: CGFloat = 280

    private var artworkURL: URL? {
        subscription?.imageURL ?? episode.imageURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            artwork
            metadata
        }
        .padding(AppTheme.Spacing.md)
        .frame(width: Self.previewWidth)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let url = artworkURL {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 56, height: 56)) { phase in
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
        .frame(width: Self.previewWidth - AppTheme.Spacing.md * 2,
               height: Self.previewWidth - AppTheme.Spacing.md * 2)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
                .strokeBorder(AppTheme.Tint.hairline, lineWidth: 0.5)
        )
    }

    private var artworkPlaceholder: some View {
        Image(systemName: "waveform")
            .font(.system(size: 56, weight: .light))
            .foregroundStyle(.secondary)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let showName = subscription?.title, !showName.isEmpty {
                Text(showName)
                    .font(AppTheme.Typography.caption)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(episode.title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(relativePublished)
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.secondary)
                if let durationLabel {
                    Text("·")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.tertiary)
                    Text(durationLabel)
                        .font(AppTheme.Typography.mono)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
