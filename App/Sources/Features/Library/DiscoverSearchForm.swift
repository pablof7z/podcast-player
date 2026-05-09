import SwiftUI

// MARK: - DiscoverSearchForm

/// "Search" segment body in `AddShowSheet`. Drives Apple's iTunes Search
/// directory — the standard "discover podcasts" surface every podcast app
/// ships. Tapping a result calls into `SubscriptionService.addSubscription`
/// (same path as the From-URL form, plus the OPML import).
///
/// **State surfaces:**
///   - empty (no query yet)    — calm prompt
///   - searching                — inline spinner
///   - has results              — list of `DiscoverResultRow`
///   - error                    — inline label above results
struct DiscoverSearchForm: View {

    let store: AppStateStore
    let onAdded: (PodcastSubscription) -> Void

    /// Wait this long after the user stops typing before firing a search.
    /// Long enough to skip mid-word taps; short enough that results feel live.
    private static let debounceMS: UInt64 = 300

    /// Auto-search only kicks in once the query is meaningful.
    private static let minAutoSearchChars: Int = 2

    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var results: [ITunesSearchClient.Result] = []
    @State private var error: String?
    @State private var subscribingID: Int?
    @State private var searchTask: Task<Void, Never>?

    /// Trending podcasts shown when the query is empty — fetched once
    /// per sheet appearance, then cached.
    @State private var trending: [ITunesSearchClient.Result] = []
    @State private var isLoadingTrending: Bool = false
    @State private var trendingFetched: Bool = false

    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.xs)
            }

            if results.isEmpty && !isSearching {
                emptyOrTrendingState
            } else {
                resultsList
            }
        }
        .onAppear {
            queryFocused = true
            if !trendingFetched {
                trendingFetched = true
                Task { await loadTrending() }
            }
        }
        .onChange(of: query) { _, newValue in
            scheduleAutoSearch(for: newValue)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Apple Podcasts", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($queryFocused)
                .onSubmit { runSearch() }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    error = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    // MARK: - Empty / results

    /// Pre-search empty area: shows the "Popular Now" rail when the
    /// trending fetch succeeded; falls back to the calm prompt when the
    /// fetch is still in flight, failed, or returned nothing.
    @ViewBuilder
    private var emptyOrTrendingState: some View {
        if !trending.isEmpty {
            trendingSection
        } else if isLoadingTrending {
            VStack {
                Spacer(minLength: 60)
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            calmPrompt
        }
    }

    private var calmPrompt: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer(minLength: 40)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Find shows on Apple Podcasts")
                .font(AppTheme.Typography.headline)
            Text("Search by show name, host, or topic.")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }

    /// "Popular Now" — top podcasts from Apple's marketing feed. Same row
    /// component (and tap-to-subscribe affordance) as search results.
    private var trendingSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("Popular Now")
                        .font(AppTheme.Typography.headline)
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xs)

                ForEach(trending) { result in
                    DiscoverResultRow(
                        result: result,
                        isSubscribing: subscribingID == result.collectionId,
                        isAlreadySubscribed: isAlreadySubscribed(result),
                        onSubscribe: { Task { await subscribe(to: result) } }
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    Divider().padding(.leading, AppTheme.Spacing.lg + 64 + AppTheme.Spacing.md)
                }
            }
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, AppTheme.Spacing.lg)
                        Spacer()
                    }
                }
                ForEach(results) { result in
                    DiscoverResultRow(
                        result: result,
                        isSubscribing: subscribingID == result.collectionId,
                        isAlreadySubscribed: isAlreadySubscribed(result),
                        onSubscribe: { Task { await subscribe(to: result) } }
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    Divider().padding(.leading, AppTheme.Spacing.lg + 64 + AppTheme.Spacing.md)
                }
            }
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Logic

    private func isAlreadySubscribed(_ result: ITunesSearchClient.Result) -> Bool {
        guard let url = result.feedURL else { return false }
        return store.subscription(feedURL: url) != nil
    }

    /// Submit-handler (return key on the keyboard). Skips the debounce so
    /// users who hit Enter get instant results.
    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { await performSearch(trimmed) }
    }

    /// Debounced as-you-type. Clears results when the field empties, skips
    /// queries shorter than `minAutoSearchChars` (no point hitting the API
    /// for a single letter), and cancels any in-flight task each keystroke.
    private func scheduleAutoSearch(for raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        if trimmed.isEmpty {
            results = []
            error = nil
            isSearching = false
            return
        }
        guard trimmed.count >= Self.minAutoSearchChars else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounceMS * 1_000_000)
            if Task.isCancelled { return }
            await performSearch(trimmed)
        }
    }

    private func performSearch(_ term: String) async {
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            let fetched = try await ITunesSearchClient.search(term)
            guard !Task.isCancelled else { return }
            results = fetched
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
            results = []
        }
    }

    /// One-shot trending fetch. Failure is silent — the calm prompt takes
    /// over so the empty state never feels broken when the network is gone.
    private func loadTrending() async {
        isLoadingTrending = true
        defer { isLoadingTrending = false }
        let fetched = (try? await ITunesSearchClient.topPodcasts()) ?? []
        trending = fetched
    }

    private func subscribe(to result: ITunesSearchClient.Result) async {
        guard let feedURL = result.feedURL else {
            error = "This show has no public feed URL."
            return
        }
        subscribingID = result.collectionId
        defer { subscribingID = nil }

        let service = SubscriptionService(store: store)
        do {
            let added = try await service.addSubscription(feedURLString: feedURL.absoluteString)
            Haptics.success()
            onAdded(added)
        } catch let addError as SubscriptionService.AddError {
            // "Already subscribed" is success-like — the row will just flip
            // to the checkmark on next render via `isAlreadySubscribed`.
            if case .alreadySubscribed = addError {
                Haptics.light()
                return
            }
            self.error = addError.localizedDescription
            Haptics.warning()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }
}

// MARK: - DiscoverResultRow

/// Row in the directory search results. Artwork left, title + author + meta
/// in the middle, subscribe button right. Replaces the trailing button with
/// a check when the user is already subscribed.
struct DiscoverResultRow: View {

    let result: ITunesSearchClient.Result
    let isSubscribing: Bool
    let isAlreadySubscribed: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(result.collectionName)
                    .font(AppTheme.Typography.headline)
                    .lineLimit(2)
                if let artist = result.artistName, !artist.isEmpty {
                    Text(artist)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                metaRow
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            subscribeButton
                .padding(.top, 2)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var artwork: some View {
        AsyncImage(url: result.artworkURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty, .failure:
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                }
            @unknown default:
                Color(.tertiarySystemFill)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous))
    }

    @ViewBuilder
    private var metaRow: some View {
        let bits: [String] = {
            var parts: [String] = []
            if let g = result.primaryGenreName, !g.isEmpty { parts.append(g) }
            if let count = result.trackCount, count > 0 {
                parts.append("\(count) episode\(count == 1 ? "" : "s")")
            }
            return parts
        }()
        if !bits.isEmpty {
            Text(bits.joined(separator: " · "))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var subscribeButton: some View {
        Button(action: onSubscribe) {
            Group {
                if isSubscribing {
                    ProgressView().controlSize(.small)
                } else if isAlreadySubscribed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .font(.title3)
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(isSubscribing || isAlreadySubscribed)
        .accessibilityLabel(
            isAlreadySubscribed
                ? "Already subscribed to \(result.collectionName)"
                : "Subscribe to \(result.collectionName)"
        )
    }
}
