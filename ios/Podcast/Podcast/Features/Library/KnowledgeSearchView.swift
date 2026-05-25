import SwiftUI
import os.log

// MARK: - KnowledgeSearchView

/// "Search across your podcast library" — semantic search over episode
/// transcripts (feature #38). The Rust kernel owns the ranker; this view
/// is a thin shell:
///
/// 1. Debounces typing by 500 ms, then dispatches
///    `podcast.knowledge.search { query }` through `KernelModel`.
/// 2. Reads results back from `snapshot.knowledgeSearchResults` on each
///    `podcastSnapshot` tick (no mirrored property — same pattern as
///    `DiscoverSearchForm` reading from `snapshot.searchResults`).
/// 3. Dispatches `podcast.knowledge.clear_results` when the query is
///    cleared so the snapshot doesn't carry stale rows into the next
///    visit.
///
/// The underlying ranker is currently a case-insensitive substring
/// match (M6.A stub); M6.B swaps in a hybrid KNN + BM25 reranker
/// without a wire-format change.
struct KnowledgeSearchView: View {

    nonisolated private static let logger = Logger.app("KnowledgeSearch")

    private static let debounceMS: UInt64 = 500
    private static let minAutoSearchChars: Int = 2

    @Environment(KernelModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var lastDispatchedQuery: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var queryFocused: Bool = false
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            content
        }
        .navigationTitle("Search Library")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            requestSearchFocus(deferred: true)
        }
        .onDisappear {
            searchTask?.cancel()
            focusTask?.cancel()
            queryFocused = false
            // Drop staged results so the next visit starts clean and the
            // snapshot stays small for other consumers.
            model.dispatch(namespace: "podcast.knowledge", body: ["op": "clear_results"])
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
            DiscoverSearchTextField(
                placeholder: "Search transcripts, titles, descriptions",
                text: $query,
                isFocused: $queryFocused,
                onSubmit: runSearch
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            Button(action: clearQuery) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(query.isEmpty ? 0 : 1)
            .disabled(query.isEmpty)
            .accessibilityHidden(query.isEmpty)
            .accessibilityLabel("Clear search")
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { requestSearchFocus() }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        let results = model.podcastSnapshot?.knowledgeSearchResults ?? []
        if results.isEmpty {
            if isQueryDispatchedAndEmpty {
                noResultsState
            } else {
                placeholderState
            }
        } else {
            resultsList(results)
        }
    }

    private var placeholderState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer(minLength: 64)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Search your podcast library")
                .font(AppTheme.Typography.headline)
            Text("Find episodes by topic, host, or any text inside the show notes.")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xl)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer(minLength: 64)
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(AppTheme.Typography.headline)
            if let term = lastDispatchedQuery {
                Text("Nothing in your library mentions \"\(term)\" yet.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xl)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func resultsList(_ results: [KnowledgeSearchResult]) -> some View {
        List {
            ForEach(results) { result in
                KnowledgeSearchResultRow(result: result, onSeek: { seek(to: result) })
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: AppTheme.Spacing.xs,
                        leading: AppTheme.Spacing.lg,
                        bottom: AppTheme.Spacing.xs,
                        trailing: AppTheme.Spacing.lg
                    ))
                    .listRowBackground(Color(.systemBackground))
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Logic

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isQueryDispatchedAndEmpty: Bool {
        guard let term = lastDispatchedQuery, !term.isEmpty else { return false }
        return term == normalizedQuery
    }

    private func requestSearchFocus(deferred: Bool = false) {
        focusTask?.cancel()
        guard deferred else { queryFocused = true; return }
        focusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            queryFocused = true
        }
    }

    private func clearQuery() {
        query = ""
        lastDispatchedQuery = nil
        model.dispatch(namespace: "podcast.knowledge", body: ["op": "clear_results"])
        requestSearchFocus()
    }

    private func runSearch() {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { dispatchSearch(trimmed) }
    }

    private func scheduleAutoSearch(for raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        if trimmed.isEmpty {
            lastDispatchedQuery = nil
            model.dispatch(namespace: "podcast.knowledge", body: ["op": "clear_results"])
            return
        }
        guard trimmed.count >= Self.minAutoSearchChars else {
            lastDispatchedQuery = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounceMS * 1_000_000)
            if Task.isCancelled { return }
            dispatchSearch(trimmed)
        }
    }

    private func dispatchSearch(_ term: String) {
        lastDispatchedQuery = term
        Self.logger.info("dispatching knowledge.search query=\(term, privacy: .public)")
        model.dispatch(namespace: "podcast.knowledge", body: ["op": "search", "query": term])
    }

    private func seek(to result: KnowledgeSearchResult) {
        Haptics.light()
        model.dispatch(
            namespace: "podcast.player",
            body: ["op": "play", "episode_id": result.episodeId]
        )
        if let secs = result.startSecs {
            model.dispatch(
                namespace: "podcast.player",
                body: ["op": "seek", "position_secs": secs]
            )
        }
        NotificationCenter.default.post(name: .openPlayerRequested, object: nil)
    }
}
