import SwiftUI

// MARK: - AppSidebarPodcastsSection

/// Compact "Podcasts" surface embedded inside the slide-in sidebar.
///
/// Mirrors the data shown by `AllPodcastsListView` (every podcast the app
/// knows about, minus the Unknown sentinel, sorted alphabetically) but keeps
/// the inline footprint small: at most `inlineLimit` rows are rendered as
/// plain buttons, and a "See All (N)" affordance opens the full list.
///
/// The sidebar is a left-anchored overlay, NOT a `NavigationStack`, so the
/// full list is presented in a `.sheet`. That sheet supplies its own
/// `NavigationStack` (and the `.navigationDestination(for: Podcast.self)` that
/// `AllPodcastsListView`'s `NavigationLink(value:)` rows depend on), plus a
/// Done button to dismiss the modal.
struct AppSidebarPodcastsSection: View {
    /// Closes the parent sidebar. Invoked before presenting the sheet so the
    /// overlay does not linger behind the modal.
    let onDismissSidebar: () -> Void

    @Environment(AppStateStore.self) private var store
    @State private var showAllPodcastsSheet = false

    /// Maximum number of podcast rows rendered inline before the section
    /// collapses to a single "See All (N)" link.
    private let inlineLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if podcasts.isEmpty {
                emptyState
            } else {
                ForEach(inlinePodcasts) { podcast in
                    row(for: podcast)
                }
                if podcasts.count > inlineLimit {
                    seeAllLink
                }
            }
        }
        .sheet(isPresented: $showAllPodcastsSheet) {
            allPodcastsSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("Podcasts")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if !podcasts.isEmpty {
                Button(action: presentSheet) {
                    Text("See All")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all podcasts")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.xs)
    }

    // MARK: - Rows

    private func row(for podcast: Podcast) -> some View {
        Button(action: presentSheet) {
            HStack(spacing: AppTheme.Spacing.sm) {
                artwork(for: podcast)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle(for: podcast))
                        .font(AppTheme.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(episodeCountLabel(for: podcast))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func artwork(for podcast: Podcast) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            podcast.accentColor.opacity(0.9),
                            podcast.accentColor.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let url = podcast.imageURL {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 88, height: 88)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderGlyph(for: podcast)
                    }
                }
            } else {
                placeholderGlyph(for: podcast)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous))
    }

    private func placeholderGlyph(for podcast: Podcast) -> some View {
        Image(systemName: podcast.artworkSymbol)
            .font(.system(size: 18, weight: .light))
            .foregroundStyle(.white.opacity(0.92))
    }

    private var seeAllLink: some View {
        Button(action: presentSheet) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("See All (\(podcasts.count))")
                    .font(AppTheme.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See all \(podcasts.count) podcasts")
    }

    private var emptyState: some View {
        Text("No podcasts yet")
            .font(AppTheme.Typography.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
    }

    // MARK: - Sheet

    private var allPodcastsSheet: some View {
        NavigationStack {
            AllPodcastsListView()
                .navigationDestination(for: Podcast.self) { podcast in
                    ShowDetailView(podcast: podcast)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { showAllPodcastsSheet = false }
                    }
                }
        }
    }

    // MARK: - Actions

    private func presentSheet() {
        Haptics.selection()
        onDismissSidebar()
        showAllPodcastsSheet = true
    }

    // MARK: - Data

    /// All podcasts excluding the built-in Unknown sentinel, sorted
    /// alphabetically — identical to `AllPodcastsListView.podcasts`.
    private var podcasts: [Podcast] {
        store.allPodcasts
            .filter { $0.id != Podcast.unknownID }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var inlinePodcasts: [Podcast] {
        Array(podcasts.prefix(inlineLimit))
    }

    private func displayTitle(for podcast: Podcast) -> String {
        if podcast.title.isEmpty {
            return podcast.feedURL?.host ?? "Untitled"
        }
        return podcast.title
    }

    private func episodeCountLabel(for podcast: Podcast) -> String {
        let count = store.episodes(forPodcast: podcast.id).count
        return count == 1 ? "1 episode" : "\(count) episodes"
    }
}
