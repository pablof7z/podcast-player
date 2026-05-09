import SwiftUI

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
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button {
                onMarkPlayed()
            } label: {
                Label("Mark as played", systemImage: "checkmark.circle")
            }
            NavigationLink {
                detailPlaceholder
            } label: {
                Label("Episode details", systemImage: "info.circle")
            }
        }
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
                AsyncImage(url: url) { phase in
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

    @ViewBuilder
    private var detailPlaceholder: some View {
        // Lane 5 owns the real EpisodeDetailView. Until the navigation
        // destination is wired through Home's NavigationStack, surface the
        // title so the navigation hop still feels intentional.
        VStack(spacing: AppTheme.Spacing.md) {
            Text(episode.title)
                .font(AppTheme.Typography.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.lg)
            if let showName = subscription?.title, !showName.isEmpty {
                Text(showName)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
