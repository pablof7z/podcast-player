import SwiftUI

// MARK: - LibraryGridCell

/// One card in the Library subscriptions grid.
///
/// **Glass usage:** matte (per the lane brief). The cell uses a
/// rounded artwork tile, a title line, and an unplayed dot — no glass.
/// The grid container itself is the only glass-allowed surface, and
/// the brief reserves it for the chrome (filter rail, search bar).
///
/// **Artwork stand-in:** Lane 3 uses an SF Symbol over a tinted gradient
/// keyed to `subscription.accentColor`. Lane 2 swaps in real artwork.
struct LibraryGridCell: View {
    let subscription: LibraryMockSubscription

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            artworkTile

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subscription.author)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                            subscription.accentColor.opacity(0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: subscription.artworkSymbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(0.92))
                        .accessibilityHidden(true)
                )
                .appShadow(AppTheme.Shadow.subtle)

            if subscription.hasUnplayed {
                unplayedDot
                    .padding(AppTheme.Spacing.sm)
            }
        }
    }

    private var unplayedDot: some View {
        ZStack {
            Circle()
                .fill(.red)
                .frame(width: 14, height: 14)
                .appShadow(AppTheme.Shadow.subtle)
            if subscription.unplayedCount > 1 {
                Text("\(min(subscription.unplayedCount, 9))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        var parts = ["\(subscription.title), \(subscription.author)"]
        if subscription.hasUnplayed {
            parts.append("\(subscription.unplayedCount) unplayed")
        }
        return parts.joined(separator: ", ")
    }
}
