import SwiftUI

// MARK: - LibraryContinueListeningRail

/// Horizontal rail surfaced at the top of the Library tab. Mirrors the
/// "Continue listening" hero on Home but caps the visible cards at three
/// — Library is a denser surface and the rail must yield vertical space to
/// the subscription grid below it.
///
/// Tapping a card pushes a `LibraryEpisodeRoute` onto the enclosing
/// `NavigationStack`. The route is registered by `LibraryView`.
struct LibraryContinueListeningRail: View {

    /// Maximum number of cards rendered. Sourced from the brief: "showing
    /// up to 3 in-progress episodes". Excess in-progress episodes still
    /// surface on the Home tab's full-length rail.
    static let maxCards: Int = 3

    let episodes: [Episode]

    @Environment(AppStateStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    ForEach(episodes.prefix(Self.maxCards)) { episode in
                        LibraryContinueListeningCard(
                            episode: episode,
                            subscription: store.subscription(id: episode.subscriptionID)
                        )
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            }
        }
    }

    private var header: some View {
        Text("Continue listening")
            .font(AppTheme.Typography.title3)
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.md)
    }
}

// MARK: - LibraryContinueListeningCard

/// Compact in-progress card. Smaller than the Home rail's hero card so the
/// rail can sit above the subscription grid without dominating the viewport.
/// Uses a circular progress arc (rather than the linear bar on Home) to
/// keep the meta strip tight and to differentiate the surface visually.
struct LibraryContinueListeningCard: View {
    let episode: Episode
    let subscription: PodcastSubscription?

    private static let cardWidth: CGFloat = 152
    private static let artworkSize: CGFloat = 136
    private static let arcSize: CGFloat = 22
    private static let arcLineWidth: CGFloat = 2.5

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                artwork
                meta
            }
            .frame(width: Self.cardWidth)
            .padding(AppTheme.Spacing.xs)
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

    private var route: LibraryEpisodeRoute {
        LibraryEpisodeRoute(
            episodeID: episode.id,
            subscriptionID: episode.subscriptionID,
            title: episode.title
        )
    }

    // MARK: - Subviews

    private var artworkURL: URL? {
        episode.imageURL ?? subscription?.imageURL
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            artworkImage
            progressArc
                .padding(6)
        }
    }

    @ViewBuilder
    private var artworkImage: some View {
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
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .strokeBorder(AppTheme.Tint.hairline, lineWidth: 0.5)
        )
    }

    private var artworkPlaceholder: some View {
        Image(systemName: "waveform")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(.secondary)
    }

    /// Circular arc rendered over the artwork's bottom-right corner. The
    /// background ring sits on a thin glass capsule so the indicator stays
    /// legible regardless of the underlying artwork.
    private var progressArc: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.35), lineWidth: Self.arcLineWidth)
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    AppTheme.Tint.agentSurface,
                    style: StrokeStyle(lineWidth: Self.arcLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Self.arcSize, height: Self.arcSize)
        .background(
            Circle().fill(.ultraThinMaterial)
        )
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let showName = subscription?.title, !showName.isEmpty {
                Text(showName)
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(episode.title)
                .font(AppTheme.Typography.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private var progressFraction: Double {
        guard let duration = episode.duration, duration > 0 else { return 0 }
        let raw = episode.playbackPosition / duration
        return max(0.02, min(1, raw))
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let showName = subscription?.title, !showName.isEmpty {
            parts.append(showName)
        }
        parts.append(episode.title)
        let percent = Int((progressFraction * 100).rounded())
        if percent > 0 { parts.append("\(percent) percent listened") }
        parts.append("Tap to open episode details")
        return parts.joined(separator: ", ")
    }
}
