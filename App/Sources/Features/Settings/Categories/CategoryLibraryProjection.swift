import Foundation

// MARK: - CategoryLibraryProjection
//
// Swift owns the legacy category display DTO. Rust owns category ordering and
// valid subscribed podcast membership for category-driven screens.

struct CategoryLibraryProjection {
    let categoryIDs: [UUID]
    let podcastIDsByCategory: [UUID: [UUID]]
    let allTranscriptionEnabledByCategory: [UUID: Bool]

    static let empty = CategoryLibraryProjection(
        categoryIDs: [], podcastIDsByCategory: [:], allTranscriptionEnabledByCategory: [:]
    )

    // `@MainActor`: reads main-actor `store.kernel`. Used by one-shot,
    // non-view call sites (e.g. `LivePodcastInventoryAdapter`'s agent-tool
    // sync helpers) that aren't re-run per SwiftUI render; SwiftUI views read
    // `loadOffMain` below instead.
    @MainActor
    static func load(categories: [PodcastCategory], store: AppStateStore) -> CategoryLibraryProjection {
        let request = categories.map { category in
            [
                "category_id": category.id.uuidString,
                "name": category.name,
                "podcast_ids": category.subscriptionIDs.map(\.uuidString),
            ] as [String: Any]
        }
        guard let envelope = store.kernel?.libraryCategoriesEnvelope(categories: request),
              let data = envelope.data(using: .utf8),
              let response = try? JSONDecoder.categoryLibraryProjection.decode(Response.self, from: data)
        else {
            return .empty
        }
        return Self.projection(from: response)
    }

    /// `nmp_app_podcast_library_categories` (the Rust side of
    /// `libraryCategoriesEnvelope`) scans `store.all_podcasts()` once per
    /// requested category. Runs off MainActor on `kernel.snapshotDecodeQueue`
    /// — a main-thread `sample` on a real ~2k-episode library caught this
    /// call landing on MainActor even when gated behind a `.task(id:)` cache
    /// (caching cuts call *frequency*, not the cost of the call that does
    /// still fire — see `AppStateStore.offMainFFI`'s doc comment). Both
    /// `HomeView` and `HomeCategoryPickerSheet` call this from a `.task(id:)`.
    @MainActor
    static func loadOffMain(categories: [PodcastCategory], store: AppStateStore) async -> CategoryLibraryProjection {
        // `[[String: Any]]` isn't `Sendable`, so the request is built INSIDE
        // the `offMainFFI` closure from `categories` (`PodcastCategory` is
        // `Sendable`) rather than captured from outside.
        let envelope = await store.offMainFFI { handle in
            let request = categories.map { category in
                [
                    "category_id": category.id.uuidString,
                    "name": category.name,
                    "podcast_ids": category.subscriptionIDs.map(\.uuidString),
                ] as [String: Any]
            }
            return handle.libraryCategoriesEnvelope(categories: request)
        }
        guard let envelope = envelope ?? nil,
              let data = envelope.data(using: .utf8),
              let response = try? JSONDecoder.categoryLibraryProjection.decode(Response.self, from: data)
        else {
            return .empty
        }
        return Self.projection(from: response)
    }

    private static func projection(from response: Response) -> CategoryLibraryProjection {
        CategoryLibraryProjection(
            categoryIDs: response.categories.map(\.categoryId),
            podcastIDsByCategory: Dictionary(
                uniqueKeysWithValues: response.categories.map { ($0.categoryId, $0.podcastIds) }
            ),
            allTranscriptionEnabledByCategory: Dictionary(
                uniqueKeysWithValues: response.categories.compactMap { row in
                    row.allTranscriptionEnabled.map { (row.categoryId, $0) }
                }
            )
        )
    }

    func sortedCategories(from categories: [PodcastCategory]) -> [PodcastCategory] {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return categoryIDs.compactMap { byID[$0] }
    }

    @MainActor
    func podcasts(in categoryID: UUID, store: AppStateStore) -> [Podcast] {
        (podcastIDsByCategory[categoryID] ?? []).compactMap { store.podcast(id: $0) }
    }

    func podcastCount(in categoryID: UUID) -> Int {
        podcastIDsByCategory[categoryID]?.count ?? 0
    }

    func categoryIDs(containing podcastID: UUID) -> [UUID] {
        categoryIDs.filter { categoryID in
            podcastIDsByCategory[categoryID]?.contains(podcastID) == true
        }
    }

    func allTranscriptionEnabled(in categoryID: UUID) -> Bool? {
        allTranscriptionEnabledByCategory[categoryID]
    }

    private struct Response: Decodable {
        let categories: [Row]
    }

    private struct Row: Decodable {
        let categoryId: UUID
        let podcastIds: [UUID]
        let allTranscriptionEnabled: Bool?
    }
}

private extension JSONDecoder {
    static let categoryLibraryProjection: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
