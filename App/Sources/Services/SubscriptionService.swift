import Foundation
import os.log

/// Coordinates `FeedClient` fetches with `AppStateStore` writes.
///
/// Single entry point shared by:
///   - "Add by URL" — first-time subscribe to an unknown feed.
///   - OPML import — enrich each parsed entry then store + episodes.
///   - Pull-to-refresh — re-fetch one show, or every show in parallel.
///
/// All work is `@MainActor`-isolated because the store is `@MainActor` and we
/// dispatch the I/O via `URLSession.shared` which already hops off-main
/// internally. Keeping this service main-actor avoids a fan of explicit
/// `await MainActor.run` blocks at the call sites.
@MainActor
struct SubscriptionService {

    private static let logger = Logger.app("SubscriptionService")

    /// Underlying feed client. Tests can pass a stub session via
    /// `FeedClient(session:)`.
    let client: FeedClient

    /// The destination store. Subscriptions and episodes both land here.
    let store: AppStateStore

    init(store: AppStateStore, client: FeedClient = FeedClient()) {
        self.store = store
        self.client = client
    }

    // MARK: - Errors surfaced to UI

    enum AddError: Error, LocalizedError, Equatable {
        case invalidURL
        case alreadySubscribed(title: String)
        case transport(String)
        case http(Int)
        case parse(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "That doesn't look like a valid feed URL."
            case .alreadySubscribed(let title):
                return "You're already subscribed to \(title)."
            case .transport(let message):
                return "Couldn't reach the feed: \(message)"
            case .http(let status):
                return Self.humanizeHTTPStatus(status)
            case .parse(let message):
                // The parse error already speaks in user-facing language
                // (see `RSSParser.ParseError.errorDescription`). Don't
                // double-prefix with "Couldn't read this feed:" — the
                // parse messages already explain the problem in full
                // sentences.
                return message
            }
        }

        /// Maps an HTTP status into the kind of plain-English sentence the
        /// rest of the error surface uses — users don't think in 404/500.
        /// Keeps the raw code as a parenthetical so support diagnostics
        /// still have a fingerprint to grep for.
        private static func humanizeHTTPStatus(_ status: Int) -> String {
            switch status {
            case 401, 403:
                return "This feed needs sign-in or isn't public — Podcastr can't subscribe to it."
            case 404, 410:
                return "We couldn't find a feed at that URL. Double-check it and try again."
            case 408, 504:
                return "The feed server took too long to respond. Try again in a moment."
            case 429:
                return "The feed server is rate-limiting requests right now. Try again in a few minutes."
            case 500..<600:
                return "The feed server hit an error (HTTP \(status)). Try again later."
            case 400..<500:
                return "The feed server rejected the request (HTTP \(status))."
            default:
                return "The feed server returned an unexpected status (HTTP \(status))."
            }
        }
    }

    // MARK: - Add by URL

    /// Subscribes to a brand-new feed URL. Fetches the feed, persists the
    /// resulting subscription, and upserts the parsed episodes.
    ///
    /// Returns the live subscription on success. Throws `AddError` for any UI-
    /// reportable failure (invalid URL, duplicate, transport, parse).
    @discardableResult
    func addSubscription(feedURLString: String) async throws -> PodcastSubscription {
        let trimmed = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedURL(from: trimmed) else {
            throw AddError.invalidURL
        }
        if let existing = store.subscription(feedURL: url) {
            throw AddError.alreadySubscribed(title: existing.title.isEmpty ? url.host ?? trimmed : existing.title)
        }
        let placeholder = PodcastSubscription(feedURL: url, title: url.host ?? trimmed)
        let result: FeedClient.FeedFetchResult
        do {
            result = try await client.fetch(placeholder)
        } catch let feedError as FeedClient.FeedFetchError {
            throw map(feedError)
        }
        switch result {
        case .updated(let subscription, let episodes, _):
            guard store.addSubscription(subscription) else {
                throw AddError.alreadySubscribed(title: subscription.title)
            }
            store.upsertEpisodes(
                episodes,
                forSubscription: subscription.id,
                evaluateAutoDownload: false
            )
            return subscription
        case .notModified:
            // First fetch can't realistically be 304 (no ETag was sent), but if
            // a server misbehaves we still want a record on disk.
            guard store.addSubscription(placeholder) else {
                throw AddError.alreadySubscribed(title: placeholder.title)
            }
            return placeholder
        }
    }

    // MARK: - Adopt a parsed OPML entry

    /// Persists a single OPML-parsed subscription, enriching it with a live
    /// fetch so the title / author / image / description come from the feed
    /// itself rather than the OPML attributes (which are usually sparse).
    ///
    /// Skips silently when an existing subscription already covers the feed
    /// URL; returns `nil` in that case so the caller can count duplicates
    /// separately from errors.
    @discardableResult
    func adopt(opmlEntry seed: PodcastSubscription) async throws -> PodcastSubscription? {
        guard let payload = try await fetchForAdoption(opmlEntry: seed) else { return nil }
        let result = store.addSubscriptions([payload])
        return result.imported == 1 ? payload.subscription : nil
    }

    /// Fetches and enriches an OPML entry without mutating the store. The
    /// import sheet uses this to gather many feeds and then commit them in
    /// one store batch, instead of forcing a growing full-state save per feed.
    func fetchForAdoption(opmlEntry seed: PodcastSubscription) async throws -> SubscriptionImportPayload? {
        if store.subscription(feedURL: seed.feedURL) != nil { return nil }
        let result: FeedClient.FeedFetchResult
        do {
            result = try await client.fetch(seed)
        } catch let feedError as FeedClient.FeedFetchError {
            throw map(feedError)
        }
        switch result {
        case .updated(let subscription, let episodes, _):
            return SubscriptionImportPayload(subscription: subscription, episodes: episodes)
        case .notModified:
            return SubscriptionImportPayload(subscription: seed, episodes: [])
        }
    }

    // MARK: - Refresh

    /// Re-fetches a single subscription and writes back the merged metadata +
    /// any new episodes. Errors are swallowed (logged in debug) so a single
    /// flaky feed doesn't poison a multi-feed refresh.
    func refresh(_ subscription: PodcastSubscription) async {
        guard let live = store.subscription(id: subscription.id) else { return }
        do {
            try await SubscriptionRefreshService(client: client).refresh(live.id, store: store)
        } catch {
            Self.logger.error("refresh failed for \(live.feedURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // (The previous `refreshAll()` here was sequential and is now superseded
    // by `SubscriptionRefreshService.refreshAll(store:)` which fans out with
    // bounded concurrency. It was removed when the Home/Library merge
    // replaced the only caller with the service-based path.)

    // MARK: - Helpers

    private func normalizedURL(from input: String) -> URL? {
        guard !input.isEmpty else { return nil }
        let candidate = input.contains("://") ? input : "https://\(input)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    private func map(_ error: FeedClient.FeedFetchError) -> AddError {
        switch error {
        case .transport(let underlying):
            return .transport(underlying)
        case .http(let status):
            return .http(status)
        case .parse(let parseError):
            // Use `errorDescription` (friendly copy on
            // `RSSParser.ParseError`) instead of `String(describing:)` —
            // the latter surfaced raw Swift case names like
            // `malformedXML(underlying: "NSXMLParserErrorDomain error 111")`
            // straight to the user.
            let message = parseError.errorDescription
                ?? (parseError as NSError).localizedDescription
            return .parse(message)
        }
    }
}
