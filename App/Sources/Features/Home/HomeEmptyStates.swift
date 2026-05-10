import SwiftUI

// MARK: - HomeFirstRunEmptyState

/// Pitch surface shown when the user has zero subscriptions. Lifted
/// verbatim from the legacy LibraryView so the onboarding moment carries
/// over unchanged.
struct HomeFirstRunEmptyState: View {
    let onAddShow: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Your shows live here.")
                    .font(AppTheme.Typography.title)
                Text("Search Apple Podcasts, paste a feed URL, or import an OPML file to begin.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Haptics.light()
                onAddShow()
            } label: {
                Label("Add Show", systemImage: "plus.circle.fill")
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - HomeFilteredEmptyState

/// "No shows match this filter" state. Distinct from the first-run state
/// so a user with 40 subs and an active Transcribed filter doesn't see
/// the onboarding pitch as if their library disappeared.
struct HomeFilteredEmptyState: View {
    let filter: LibraryFilter
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: filter.emptyStateGlyph)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: AppTheme.Spacing.xs) {
                Text(filter.emptyStateTitle)
                    .font(AppTheme.Typography.title)
                Text(filter.emptyStateSubtitle)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Haptics.light()
                onClearFilters()
            } label: {
                Label("Clear filters", systemImage: "line.3.horizontal.decrease.circle")
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}
