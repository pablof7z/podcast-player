import SwiftUI

// MARK: - ShowDetailHeader

/// Hero header for `ShowDetailView` — large square artwork (real image when
/// `imageURL` is present; SF symbol stand-in otherwise), title, author, and
/// episode count.
///
/// **Tint:** the background is a vertical gradient sourced from the
/// subscription's `accentColor`, fading to `Color(.systemBackground)` roughly
/// 30% down the header's height — this matches ux-02 §4 ("Show-detail header
/// inherits a dominant tint extracted from artwork, fading to background by
/// 30% height").
///
/// **Glass:** none. The header is a matte editorial surface.
struct ShowDetailHeader: View {
    let subscription: PodcastSubscription
    let episodeCount: Int

    var body: some View {
        ZStack(alignment: .top) {
            tintGradient
            VStack(spacing: AppTheme.Spacing.md) {
                artwork
                    .padding(.top, AppTheme.Spacing.lg)

                VStack(spacing: AppTheme.Spacing.xs) {
                    Text(subscription.title)
                        .font(AppTheme.Typography.largeTitle)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if !subscription.author.isEmpty {
                        Text(subscription.author)
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)

                metaRow
            }
            .padding(.bottom, AppTheme.Spacing.lg)
        }
    }

    // MARK: - Pieces

    private var tintGradient: some View {
        LinearGradient(
            colors: [
                subscription.accentColor.opacity(0.55),
                subscription.accentColor.opacity(0.18),
                Color(.systemBackground).opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 360)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }

    private var artwork: some View {
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
            .overlay(artworkOverlay)
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
            .appShadow(AppTheme.Shadow.lifted)
    }

    @ViewBuilder
    private var artworkOverlay: some View {
        if let url = subscription.imageURL {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    artworkSymbol
                }
            }
        } else {
            artworkSymbol
        }
    }

    private var artworkSymbol: some View {
        Image(systemName: subscription.artworkSymbol)
            .font(.system(size: 88, weight: .light))
            .foregroundStyle(.white.opacity(0.92))
            .accessibilityHidden(true)
    }

    private var metaRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("\(episodeCount) \(episodeCount == 1 ? "episode" : "episodes")")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            if let refreshed = subscription.lastRefreshedAt {
                Text("·")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
                Text("Updated \(relative(refreshed))")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, AppTheme.Spacing.xs)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
