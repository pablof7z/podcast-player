import SwiftUI

// MARK: - AgentPickCard

/// One large card in the Home "Agent Picks" horizontal rail.
///
/// Renders the pick's artwork as a 220-pt square hero, with the episode
/// title + podcast name + reason chip overlaid on a bottom gradient. The
/// card is decorative-only — tap routing happens in the enclosing
/// `HomeView` (`NavigationLink(value: EpisodeRoute(...))`).
///
/// `pickReason` is rendered exactly as Rust emitted it (e.g.
/// `"New from {podcast_title}"`); the iOS layer does not localize it.
struct AgentPickCard: View {

    let pick: AgentPickSummary

    /// Card width — chosen so two cards peek into view on a 390-pt
    /// device (iPhone 14 Pro), nudging the user to scroll.
    static let width: CGFloat = 220

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            gradient
            textOverlay
        }
        .frame(width: Self.width, height: Self.width)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        .appShadow(AppTheme.Shadow.subtle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {
        if let urlStr = pick.artworkUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.accentColor.opacity(0.35)
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Overlays

    /// Bottom gradient that fades artwork to near-black so the text
    /// remains legible regardless of the underlying image's luminance.
    private var gradient: some View {
        LinearGradient(
            colors: [.black.opacity(0.0), .black.opacity(0.7)],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            reasonChip

            Text(pick.episodeTitle)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

            Text(pick.podcastTitle)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reasonChip: some View {
        Text(pick.pickReason)
            .font(AppTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.accentColor.opacity(0.85))
            )
            .lineLimit(1)
    }

    private var accessibilityLabel: String {
        "\(pick.episodeTitle), \(pick.podcastTitle). \(pick.pickReason)."
    }
}
