import SwiftUI

// MARK: - LibraryGridCell

/// One card in the Library subscriptions grid.
///
/// **Glass usage:** matte. The cell uses a rounded artwork tile, a title line,
/// and an unplayed dot — no glass. The grid container itself is the only glass-
/// allowed surface, and the brief reserves it for the chrome (filter rail,
/// search bar).
///
/// Artwork is loaded asynchronously from `subscription.imageURL`; while the
/// image is in-flight (or absent) we render a tinted SF Symbol stand-in keyed
/// to `subscription.accentColor`.
struct LibraryGridCell: View {
    let subscription: PodcastSubscription
    let unplayedCount: Int
    let category: PodcastCategory?

    init(
        subscription: PodcastSubscription,
        unplayedCount: Int,
        category: PodcastCategory? = nil
    ) {
        self.subscription = subscription
        self.unplayedCount = unplayedCount
        self.category = category
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            artworkTile

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !subscription.author.isEmpty {
                    Text(subscription.author)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let category {
                    categoryBadge(category)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private var artworkTile: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
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
                .aspectRatio(1, contentMode: .fit)
                .overlay(artworkOverlay)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
                .appShadow(AppTheme.Shadow.subtle)

            if unplayedCount > 0 {
                unplayedDot
                    .padding(AppTheme.Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private var artworkOverlay: some View {
        if let url = subscription.imageURL {
            CachedAsyncImage(url: url, targetSize: CGSize(width: 150, height: 150)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    symbolPlaceholder
                }
            }
        } else {
            symbolPlaceholder
        }
    }

    private var symbolPlaceholder: some View {
        Image(systemName: subscription.artworkSymbol)
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(.white.opacity(0.92))
            .accessibilityHidden(true)
    }

    private var unplayedDot: some View {
        // iOS-standard cap: show 1–9 verbatim, 10–99 verbatim with a
        // smaller font, "99+" past the threshold. Previously the badge
        // capped at "9" so a show with 9 unplayed and one with 90
        // looked identical to the user.
        ZStack {
            Circle()
                .fill(.red)
                .frame(width: badgeWidth, height: 14)
                .appShadow(AppTheme.Shadow.subtle)
            if unplayedCount > 1 {
                Text(unplayedCountLabel)
                    .font(.system(size: badgeFontSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }

    /// 14pt circle for single-digit counts; pill stretches horizontally
    /// for two-digit and the "99+" string so the digits don't get
    /// clipped against the show artwork's corner.
    private var badgeWidth: CGFloat {
        switch unplayedCount {
        case ..<10:  return 14
        case ..<100: return 18
        default:     return 24
        }
    }

    /// Font size shrinks from 9pt → 8pt → 7pt as the digits widen so
    /// the text always sits cleanly inside the badge without going
    /// monospaced (which would clash with the rounded counts elsewhere
    /// in the grid).
    private var badgeFontSize: CGFloat {
        switch unplayedCount {
        case ..<10:  return 9
        case ..<100: return 8
        default:     return 7
        }
    }

    private var unplayedCountLabel: String {
        unplayedCount > 99 ? "99+" : "\(unplayedCount)"
    }

    private func categoryBadge(_ category: PodcastCategory) -> some View {
        Text(category.name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.xs)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: Capsule(style: .continuous))
            .padding(.top, 2)
    }

    private var accessibilityLabel: String {
        var parts = [subscription.title]
        if !subscription.author.isEmpty { parts.append(subscription.author) }
        if let category { parts.append(category.name) }
        if unplayedCount > 0 { parts.append("\(unplayedCount) unplayed") }
        return parts.joined(separator: ", ")
    }
}
