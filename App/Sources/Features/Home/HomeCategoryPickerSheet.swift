import SwiftUI

// MARK: - HomeCategoryPickerSheet
//
// Sheet opened from the Home navigation title. Shows all available
// categories as rich HomeCategoryCards (artwork strip + LLM description +
// show/episode stats) plus a top "Home" row that resets to the global
// all-categories view.
//
// Selection forwards through `onSelect`; the sheet self-dismisses after
// each pick. The caller owns persistence (via @AppStorage on categoryFilterID).

struct HomeCategoryPickerSheet: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let selectedCategoryID: UUID?
    let onSelect: (UUID?) -> Void

    /// `sortedCategories`/`categoryCardProjections` are both FFI round trips
    /// whose Rust side scans the whole library
    /// (`nmp_app_podcast_library_categories` /
    /// `nmp_app_podcast_home_category_cards`, both iterate
    /// `store.all_podcasts()`; the card-projection call additionally does a
    /// per-episode triage lookup for every podcast in every category). Both
    /// used to be plain computed properties re-run on every SwiftUI body
    /// pass — the same bug class fixed on `HomeView` itself (#755
    /// follow-up), reintroduced here since this sheet independently calls
    /// the identical category-projection helper. Cached behind `@State` +
    /// `.task(id: store.state.categories)`, same key `HomeView` uses for its
    /// own `cachedCategoryProjection`.
    @State private var cachedSortedCategories: [PodcastCategory] = []
    @State private var cachedCategoryCardProjections: [UUID: CategoryCardProjection] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    homeSection
                    if !sortedCategories.isEmpty {
                        categoriesSection
                    }
                }
                .padding(AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { categoryID in
                CategoryDetailView(categoryID: categoryID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.light()
                        dismiss()
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .task(id: store.state.categories) {
            let sorted = await CategoryLibraryProjection
                .loadOffMain(categories: store.state.categories, store: store)
                .sortedCategories(from: store.state.categories)
            cachedSortedCategories = sorted
            cachedCategoryCardProjections = await Self.loadCategoryCardProjections(
                sortedCategories: sorted, store: store
            )
        }
    }

    // MARK: - Sections

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            homeRow
        }
    }

    private var categoriesSection: some View {
        let cardProjections = categoryCardProjections
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            sectionLabel("Categories")
                .padding(.top, AppTheme.Spacing.md)
            ForEach(sortedCategories) { category in
                categoryCard(category, projection: cardProjections[category.id])
            }
        }
    }

    // MARK: - Home row

    private var homeRow: some View {
        let isActive = selectedCategoryID == nil
        return Button {
            Haptics.light()
            onSelect(nil)
            dismiss()
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                homeIcon
                homeLabels
                Spacer(minLength: 0)
                if isActive {
                    checkmark
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(rowBackground(isActive: isActive))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private var homeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
            Image(systemName: "house.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var homeLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Home")
                .font(AppTheme.Typography.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("All categories · \(store.rustFollowedPodcastCount()) shows")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.accentColor)
    }

    private func rowBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1.5
                    )
            )
    }

    // MARK: - Category card
    //
    // ZStack overlays a gear NavigationLink at the top-trailing corner.
    // SwiftUI gives the deepest interactive control gesture priority, so
    // tapping the gear navigates to CategoryDetailView (within the same
    // NavigationStack) while tapping elsewhere on the card selects the
    // category and dismisses the sheet.

    private func categoryCard(_ category: PodcastCategory, projection: CategoryCardProjection?) -> some View {
        ZStack(alignment: .topTrailing) {
            HomeCategoryCard(
                category: category,
                subscriptions: projection?.subscriptions(in: store) ?? [],
                unplayedTotal: projection?.unplayedTotal ?? 0,
                isSelected: selectedCategoryID == category.id,
                onTap: {
                    Haptics.light()
                    onSelect(category.id)
                    dismiss()
                }
            )
            NavigationLink(value: category.id) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(AppTheme.Spacing.md)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.Typography.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }

    private var sortedCategories: [PodcastCategory] { cachedSortedCategories }

    private var categoryCardProjections: [UUID: CategoryCardProjection] { cachedCategoryCardProjections }

    /// `nmp_app_podcast_home_category_cards` scans `store.all_podcasts()`
    /// once per category and does a per-episode triage lookup on top — the
    /// most expensive call found in the #755 follow-up main-thread `sample`
    /// audit of this bug class. Runs off MainActor on
    /// `kernel.snapshotDecodeQueue` (see `AppStateStore.offMainFFI`).
    @MainActor
    private static func loadCategoryCardProjections(
        sortedCategories: [PodcastCategory], store: AppStateStore
    ) async -> [UUID: CategoryCardProjection] {
        // `[[String: Any]]` isn't `Sendable`, so the request is built INSIDE
        // the `offMainFFI` closure from `sortedCategories` (`PodcastCategory`
        // is `Sendable`) rather than captured from outside.
        let envelope = await store.offMainFFI { handle in
            let request = sortedCategories.map { category in
                [
                    "category_id": category.id.uuidString,
                    "podcast_ids": category.subscriptionIDs.map(\.uuidString),
                ] as [String: Any]
            }
            return handle.homeCategoryCardsEnvelope(categories: request)
        }
        guard let envelope = envelope ?? nil,
              let data = envelope.data(using: .utf8),
              let response = try? JSONDecoder.homeCategoryCards.decode(CategoryCardsResponse.self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: response.categories.map { ($0.categoryId, $0) })
    }
}

private struct CategoryCardsResponse: Decodable {
    let categories: [CategoryCardProjection]
}

private struct CategoryCardProjection: Decodable {
    let categoryId: UUID
    let podcastIds: [UUID]
    let unplayedTotal: Int

    @MainActor
    func subscriptions(in store: AppStateStore) -> [Podcast] {
        podcastIds.compactMap { store.podcast(id: $0) }
    }
}

private extension JSONDecoder {
    static let homeCategoryCards: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
