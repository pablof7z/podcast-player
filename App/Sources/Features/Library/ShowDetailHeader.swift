import SwiftUI

// MARK: - ShowDetailHeader

/// Hero header for `ShowDetailView` — large square artwork (SF Symbol
/// in Lane 3, real image in Lane 2), title, author, episode count and
/// the "Subscribed" badge, then a row of affordances (wiki, transcripts).
///
/// **Tint:** the background is a vertical gradient sourced from the
/// subscription's `accentColor`, fading to `Color(.systemBackground)`
/// roughly 30% down the header's height — this matches ux-02 §4
/// ("Show-detail header inherits a dominant tint extracted from
/// artwork, fading to background by 30% height").
///
/// **Glass:** none. The header is a matte editorial surface; the only
/// glass on this screen lives in the toolbar (system) and the
/// "Settings for this show" sheet.
struct ShowDetailHeader: View {
    let subscription: LibraryMockSubscription
    let onSubscribeToggle: () -> Void

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

                    Text(subscription.author)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)

                metaRow
                affordanceRow
                actionRow
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
                Color(.systemBackground).opacity(0.0),
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
                        subscription.accentColor.opacity(0.55),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: subscription.artworkSymbol)
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(.white.opacity(0.92))
                    .accessibilityHidden(true)
            )
            .frame(width: 220, height: 220)
            .appShadow(AppTheme.Shadow.lifted)
    }

    private var metaRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("\(subscription.episodeCount) episodes")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            if subscription.isSubscribed {
                Text("·")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
                Label("Subscribed", systemImage: "checkmark.seal.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(subscription.accentColor)
            }
        }
        .padding(.top, AppTheme.Spacing.xs)
    }

    @ViewBuilder
    private var affordanceRow: some View {
        let items: [(symbol: String, label: String, on: Bool)] = [
            ("sparkles", "Wiki ready", subscription.wikiReady),
            ("text.bubble.fill", "Transcripts on", subscription.transcriptsEnabled),
        ]
        HStack(spacing: AppTheme.Spacing.md) {
            ForEach(items, id: \.label) { item in
                Label(item.label, systemImage: item.symbol)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(item.on ? Color.primary : Color.secondary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                    .opacity(item.on ? 1.0 : 0.55)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button {
                Haptics.medium()
                onSubscribeToggle()
            } label: {
                Label(
                    subscription.isSubscribed ? "Subscribed" : "Subscribe",
                    systemImage: subscription.isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glassProminent)
            .tint(subscription.accentColor)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.sm)
    }
}
