import SwiftUI

// MARK: - HomeSubscriptionRow

/// Compact list row for the merged Home subscription list. 40-pt artwork on
/// the leading edge, show title + most-recent-episode preview in the
/// middle, and a recency pill on the trailing edge. Long-press surfaces
/// the same context menu (Refresh / Unsubscribe) the old grid used so the
/// existing muscle memory carries over.
struct HomeSubscriptionRow: View {
    let subscription: PodcastSubscription
    let mostRecentEpisode: Episode?
    let unplayedCount: Int
    let now: Date
    /// Fired when the user picks "Unsubscribe" from the context menu. The
    /// parent owns the confirmation alert (so the destructive flow lives
    /// next to the rest of the list state, not inside the row).
    let onRequestUnsubscribe: () -> Void

    var body: some View {
        NavigationLink(value: subscription) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                artwork
                meta
                Spacer(minLength: AppTheme.Spacing.sm)
                recencyPill
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            SubscriptionContextMenu(
                subscription: subscription,
                onRequestUnsubscribe: onRequestUnsubscribe
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var artwork: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                subscription.accentColor.opacity(0.95),
                                subscription.accentColor.opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if let url = subscription.imageURL {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: subscription.artworkSymbol)
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                } else {
                    Image(systemName: subscription.artworkSymbol)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous))

            if unplayedCount > 0 {
                unplayedBadge
                    .offset(x: 6, y: -6)
            }
        }
    }

    private var unplayedBadge: some View {
        // Mirrors the LibraryGridCell badge (1-9 / 10-99 / 99+). Slightly
        // smaller font tier here because the row artwork is half the grid
        // tile size.
        ZStack {
            Capsule(style: .continuous)
                .fill(.red)
                .frame(width: badgeWidth, height: 14)
                .appShadow(AppTheme.Shadow.subtle)
            Text(badgeLabel)
                .font(.system(size: badgeFontSize, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var badgeWidth: CGFloat {
        switch unplayedCount {
        case ..<10:  return 14
        case ..<100: return 18
        default:     return 24
        }
    }

    private var badgeFontSize: CGFloat {
        switch unplayedCount {
        case ..<10:  return 9
        case ..<100: return 8
        default:     return 7
        }
    }

    private var badgeLabel: String {
        unplayedCount > 99 ? "99+" : "\(unplayedCount)"
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subscription.title)
                .font(AppTheme.Typography.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let preview = mostRecentEpisodePreview {
                Text(preview)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var recencyPill: some View {
        Text(recencyLabel)
            .font(AppTheme.Typography.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.xs)
            .padding(.vertical, 2)
    }

    // MARK: - Helpers

    /// Stripped, single-line preview of the most-recent-episode title.
    /// Falls back to a "no episodes yet" hint when the show has no
    /// episodes — the row still renders so the user can tap through to
    /// the show detail and pull-to-refresh there.
    private var mostRecentEpisodePreview: String? {
        guard let ep = mostRecentEpisode else {
            return "No episodes yet"
        }
        let title = ep.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// Recency label using the existing `RelativeTimestamp.extended`
    /// formatter — same "2h ago" / "3w ago" / abbreviated date strings
    /// used elsewhere so the surface stays visually consistent.
    private var recencyLabel: String {
        guard let date = mostRecentEpisode?.pubDate else {
            return "—"
        }
        return RelativeTimestamp.extended(date, now: now)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [subscription.title]
        if let preview = mostRecentEpisodePreview { parts.append(preview) }
        parts.append("Last episode \(recencyLabel)")
        if unplayedCount > 0 { parts.append("\(unplayedCount) unplayed") }
        return parts.joined(separator: ", ")
    }
}
