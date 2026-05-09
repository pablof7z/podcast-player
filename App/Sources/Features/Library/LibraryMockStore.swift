import SwiftUI

// MARK: - LibraryMockSubscription

/// Inline shim subscription model for Lane 3 (Library UI).
///
/// The shape mirrors what Lane 2 (`Podcast/`) is expected to land — id,
/// title, author, artwork hint, episode count, unplayed count, accent
/// tint and subscription state. The orchestrator will reconcile names at
/// merge.
///
/// **Why a shim:** Lane 3 ships UI before Lane 2's model is in main.
/// Keeping the type local here means this lane builds and runs
/// standalone; the merge swap is a single typealias rename plus a
/// dependency-injection point on `LibraryView`/`ShowDetailView`.
struct LibraryMockSubscription: Identifiable, Hashable {
    let id: UUID
    /// Show title — e.g. "The Tim Ferriss Show".
    let title: String
    /// Show host or author.
    let author: String
    /// SF Symbol used as a stand-in for cover art. Lane 2 swaps this for
    /// a real artwork URL + cached image pipeline.
    let artworkSymbol: String
    /// Stable per-show accent tint. Lane 3 hard-codes from the seed; Lane
    /// 2 should compute this from the dominant artwork color.
    let accentHue: Double
    /// Total episode count published.
    let episodeCount: Int
    /// Episodes the user has not played yet (drives the red dot badge).
    let unplayedCount: Int
    /// Whether the user is subscribed. False on a "browse" detail view.
    let isSubscribed: Bool
    /// Whether the auto-generated wiki for this show is ready.
    let wikiReady: Bool
    /// Whether transcripts are enabled for this subscription.
    let transcriptsEnabled: Bool
    /// One-paragraph show description for the detail header.
    let showDescription: String

    /// Derived `Color` from `accentHue` for the artwork-tinted detail
    /// header gradient. Always full-saturation, mid-luminance so the
    /// gradient reads on both light and dark backgrounds.
    var accentColor: Color {
        Color(hue: accentHue, saturation: 0.65, brightness: 0.78)
    }

    /// Whether this show should display the unplayed indicator dot.
    var hasUnplayed: Bool { unplayedCount > 0 }
}

// MARK: - LibraryMockEpisode

/// Inline shim episode model. Lane 2 will replace it with the real
/// `Episode` type; the field set here mirrors the spec wireframes
/// (episode number, title, duration, publication date, played /
/// download / transcription state).
struct LibraryMockEpisode: Identifiable, Hashable {
    let id: UUID
    /// Subscription this episode belongs to.
    let subscriptionID: UUID
    /// Publisher episode number (e.g. `812` for Tim Ferriss).
    let number: Int
    /// Episode title.
    let title: String
    /// One-line summary used as the row's secondary line.
    let summary: String
    /// Total runtime in seconds.
    let durationSeconds: Int
    /// Publication date (used for the "Yesterday" / "3d ago" subhead).
    let publishedAt: Date
    /// Whether the user has marked this episode played (or auto-played
    /// past the completion threshold).
    let isPlayed: Bool
    /// Listening progress in `0...1`. `0` if never played; `1` if
    /// completed. Values in-between drive the partial-progress crescent.
    let playbackProgress: Double
    /// Download / transcription state for the row capsule.
    let downloadStatus: DownloadStatus

    /// `true` when the user has listened to this episode at all but has
    /// not finished it — drives the crescent indicator on the row.
    var isInProgress: Bool {
        playbackProgress > 0.0001 && playbackProgress < 0.999 && !isPlayed
    }

    /// `true` when the user has never started this episode.
    var isUnplayed: Bool {
        !isPlayed && playbackProgress < 0.0001
    }

    /// Pretty duration string for display: "2h 14m" or "47m".
    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - LibraryMockStore

/// In-memory `@Observable` store seeded with believable subscriptions
/// and episodes for Lane 3 development. Designed for trivial DI swap by
/// Lane 2: every `LibraryView` / `ShowDetailView` accepts the store via
/// the environment, and the type is the single rename point at merge.
@MainActor
@Observable
final class LibraryMockStore {

    var subscriptions: [LibraryMockSubscription]
    var episodesBySubscription: [UUID: [LibraryMockEpisode]]

    init() {
        let seed = Self.seed()
        self.subscriptions = seed.subscriptions
        self.episodesBySubscription = seed.episodes
    }

    // MARK: - Queries

    /// Episodes for a given show, newest first.
    func episodes(for subscription: LibraryMockSubscription) -> [LibraryMockEpisode] {
        (episodesBySubscription[subscription.id] ?? [])
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// Apply a `LibraryFilter` to the subscriptions grid. The filter
    /// runs over **derived per-show stats** (any unplayed, any
    /// downloaded, transcripts enabled) so the user gets a meaningful
    /// narrowing without the filter knowing about individual episodes.
    func filteredSubscriptions(_ filter: LibraryFilter) -> [LibraryMockSubscription] {
        switch filter {
        case .all:
            return subscriptions
        case .unplayed:
            return subscriptions.filter(\.hasUnplayed)
        case .downloaded:
            return subscriptions.filter { sub in
                (episodesBySubscription[sub.id] ?? []).contains { ep in
                    if case .downloaded = ep.downloadStatus { return true }
                    return false
                }
            }
        case .transcribed:
            return subscriptions.filter(\.transcriptsEnabled)
        }
    }

    // MARK: - Mutations (mock-only)

    /// Toggle the subscribed state — used by the Subscribe button on
    /// `ShowDetailView`. Lane 2 will redirect this to the real
    /// subscription service.
    func toggleSubscription(_ id: UUID) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        let cur = subscriptions[idx]
        subscriptions[idx] = LibraryMockSubscription(
            id: cur.id,
            title: cur.title,
            author: cur.author,
            artworkSymbol: cur.artworkSymbol,
            accentHue: cur.accentHue,
            episodeCount: cur.episodeCount,
            unplayedCount: cur.unplayedCount,
            isSubscribed: !cur.isSubscribed,
            wikiReady: cur.wikiReady,
            transcriptsEnabled: cur.transcriptsEnabled,
            showDescription: cur.showDescription
        )
    }

    /// Mock OPML import. Pretends to take 1.6s; pushes a single new
    /// subscription. Lane 2 swaps in the real OPML parser.
    func importMockOPML(addingShows count: Int) async {
        // Animate the progress sheet for a moment so the import-progress
        // affordance is visible during dev review; replace at merge.
        try? await Task.sleep(for: .milliseconds(1_600))
        for i in 0..<count {
            subscriptions.append(LibraryMockStoreSeed.makeImported(index: i))
        }
    }

    // MARK: - Seed delegation

    private static func seed() -> (subscriptions: [LibraryMockSubscription],
                                   episodes: [UUID: [LibraryMockEpisode]]) {
        LibraryMockStoreSeed.build()
    }
}

// MARK: - Injection seam (Lane 2)
//
// All consumers in Lane 3 (`LibraryView`, `ShowDetailView`,
// `OPMLImportSheet`) receive the store as an explicit `let store:
// LibraryMockStore` property. There is intentionally no
// `EnvironmentKey` here — the lane stays simple, and the orchestrator
// can decide at merge whether to keep prop-passing or promote Lane 2's
// real store into `AppStateStore`.
