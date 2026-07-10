import Foundation

// MARK: - HomeView Home/category projections
//
// Split out of `HomeView.swift` (AGENTS.md 500-line hard cap) — and NOT
// merely for size. Every computed property here wraps a Rust FFI call that
// scans the full library (O(episodes) or O(podcasts × episodes)). Each used
// to be a plain SwiftUI computed property, re-run on every body pass. On a
// real ~2k-episode library, a main-thread `sample` caught these pegging the
// main thread — the sustained freeze the owner hit, not just a slow launch
// (#755 follow-up; #758 fixed `categoryProjection` the same way but missed
// `library_summary`/`home_triage_rollup`/`home_continue_listening`/
// `home_subscription_list`, fixed here).
//
// Every property below is cached behind a `@State` var declared on
// `HomeView` itself (`cached...`, in HomeView.swift — SwiftUI `@State` must
// be a stored property of the view struct, so it can't live in an
// extension) and refreshed by a `.task(id:)` in `HomeView.body`. Cache keys
// deliberately use `podcastSnapshot?.rev` rather than the raw episode
// array or a "just changed" flag: the content hash backing that rev already
// tracks in-progress/recent-unplayed *membership* changes (built for
// `KernelModelHashing.swift`'s `agentContext` hashing, for the exact same
// reason) while excluding volatile position ticks — so these stay both
// correct (update when an episode starts/finishes, when triage runs, etc.)
// and warm (don't invalidate at the 4 Hz playback emit rate).
extension HomeView {

    // MARK: Threaded Today

    var topActiveThread: ThreadingInferenceService.ActiveTopic? { cachedTopActiveThread }

    struct TopActiveThreadKey: Equatable {
        var episodeCount: Int
        var totalUnplayed: Int
        var mentionCount: Int
        var categoryID: UUID?
    }

    var topActiveThreadKey: TopActiveThreadKey {
        TopActiveThreadKey(
            episodeCount: store.rustEpisodeCount(),
            totalUnplayed: store.rustTotalUnplayedCount(),
            mentionCount: store.threadingProjection.mentions.count,
            categoryID: selectedCategoryID
        )
    }

    // MARK: Category scope

    var categoryProjection: CategoryLibraryProjection {
        cachedCategoryProjection
    }

    /// Subscription-id set for the active category, or `nil` for All.
    /// Rust resolves valid category membership; Swift passes the renderer
    /// scope through to Rust-owned Home projections and native row builders.
    var allowedSubscriptionIDs: Set<UUID>? {
        guard let id = selectedCategoryID else { return nil }
        return Set(categoryProjection.podcastIDsByCategory[id] ?? [])
    }

    /// Resolved `PodcastCategory` for the active filter, or `nil` for All.
    var activeCategory: PodcastCategory? {
        guard let id = selectedCategoryID else { return nil }
        return store.category(id: id)
    }

    var selectedCategoryID: UUID? {
        guard let id = UUID(uuidString: categoryFilterID),
              categoryProjection.categoryIDs.contains(id) else { return nil }
        return id
    }

    // MARK: Triage roll-up

    /// Roll-up of the agent's triage decisions for the subtitle under the
    /// Inbox section header. Rust owns the count semantics and active-category
    /// scope; Swift passes only the renderer's podcast-id scope and displays
    /// the returned values.
    var triageCounts: (inbox: Int, archived: Int, shows: Int) { cachedTriageCounts }

    func computeTriageCounts() async -> (inbox: Int, archived: Int, shows: Int) {
        let interval = signposter.beginInterval("triageCounts")
        defer { signposter.endInterval("triageCounts", interval) }
        let podcastIDs = allowedSubscriptionIDs.map { Array($0) } ?? []
        let envelope = await store.offMainFFI { handle in
            handle.homeTriageRollupEnvelope(podcastIDs: podcastIDs)
        }
        let decoder = JSONDecoder()
        guard let envelope = envelope ?? nil,
              let data = envelope.data(using: .utf8),
              let decoded = try? decoder.decode(HomeTriageRollupEnvelope.self, from: data)
        else { return (0, 0, 0) }
        return (decoded.inbox, decoded.archived, decoded.shows)
    }

    struct TriageCountsKey: Equatable {
        var podcastIDs: Set<UUID>?
        var lastTriagedAt: Date?
    }

    var triageCountsKey: TriageCountsKey {
        TriageCountsKey(podcastIDs: allowedSubscriptionIDs, lastTriagedAt: inboxLastTriagedAt)
    }

    var inboxLastTriagedAt: Date? {
        guard let timestamp = store.kernel?.podcastSnapshot?.inboxLastTriagedAt else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    // MARK: Continue listening

    /// In-progress episodes for the Continue Listening section. Rust owns the
    /// product filter (unplayed, non-archived, started, last two weeks, active
    /// category scope) and returns ordered episode ids; Swift resolves them for
    /// native row rendering.
    var continueListeningEpisodes: [Episode] { cachedContinueListeningEpisodes }

    func computeContinueListeningEpisodes() async -> [Episode] {
        let podcastIDs = allowedSubscriptionIDs.map { Array($0) } ?? []
        let envelope = await store.offMainFFI { handle in
            handle.homeContinueListeningEnvelope(limit: 20, podcastIDs: podcastIDs)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = envelope ?? nil,
              let data = envelope.data(using: .utf8),
              let decoded = try? decoder.decode(HomeContinueListeningEnvelope.self, from: data)
        else { return [] }
        return decoded.episodeIds
            .compactMap { UUID(uuidString: $0) }
            .compactMap { store.episode(id: $0) }
    }

    struct ContinueListeningKey: Equatable {
        var podcastIDs: Set<UUID>?
        var snapshotRev: Int?
    }

    var continueListeningKey: ContinueListeningKey {
        ContinueListeningKey(podcastIDs: allowedSubscriptionIDs, snapshotRev: store.kernel?.podcastSnapshot?.rev)
    }

    // MARK: Filtered subscriptions
    //
    // Filters apply to the subscription list ONLY — featured is curated.
    // Rust owns subscription visibility and ordering; Swift passes the active
    // filter/category scope and resolves the returned ids for native rows.

    /// `homeSubscriptionListEnvelope` scans every episode of every allowed
    /// podcast for the `unplayed` / `downloaded` / `transcribed` filters (see
    /// `home_projection.rs`).
    var filteredSubs: [Podcast] { cachedFilteredSubs }

    func computeFilteredSubs() async -> [Podcast] {
        let podcastIDs = allowedSubscriptionIDs.map { Array($0) } ?? []
        let filterRaw = filter.rawValue
        let envelope = await store.offMainFFI { handle in
            handle.homeSubscriptionListEnvelope(filter: filterRaw, podcastIDs: podcastIDs)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = envelope ?? nil,
              let data = envelope.data(using: .utf8),
              let decoded = try? decoder.decode(HomeSubscriptionListEnvelope.self, from: data)
        else { return [] }
        return decoded.podcastIds
            .compactMap { UUID(uuidString: $0) }
            .compactMap { store.podcast(id: $0) }
    }

    struct FilteredSubsKey: Equatable {
        var podcastIDs: Set<UUID>?
        var filter: LibraryFilter
        var snapshotRev: Int?
    }

    var filteredSubsKey: FilteredSubsKey {
        FilteredSubsKey(
            podcastIDs: allowedSubscriptionIDs,
            filter: filter,
            snapshotRev: store.kernel?.podcastSnapshot?.rev
        )
    }
}

struct HomeContinueListeningEnvelope: Decodable {
    var episodeIds: [String] = []

    // Explicit CodingKeys: a custom `init(from:)` on a Decodable-only type with
    // an all-defaulted stored property suppresses synthesized `CodingKeys`.
    private enum CodingKeys: String, CodingKey {
        case episodeIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episodeIds = try c.decodeIfPresent([String].self, forKey: .episodeIds) ?? []
    }
}

struct HomeTriageRollupEnvelope: Decodable {
    var inbox: Int = 0
    var archived: Int = 0
    var shows: Int = 0
}

struct HomeSubscriptionListEnvelope: Decodable {
    var podcastIds: [String] = []
}
