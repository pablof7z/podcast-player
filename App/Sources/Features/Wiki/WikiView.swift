import SwiftUI

// MARK: - Wiki home

/// Library-of-wikis home. Lists every `WikiPage` persisted by
/// `WikiStorage`, grouped by recency (Today / Yesterday / This Week /
/// Older), filterable through a search bar, and gated by a "+" toolbar
/// button that presents `WikiGenerateSheet` for compiling a new page.
///
/// All data is real — no fixtures. Empty store yields the empty state.
struct WikiView: View {

    @State private var model = WikiHomeViewModel()
    @State private var generateSheet = false
    @State private var selectedPage: WikiPage?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Wiki")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .searchable(
                    text: $model.searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search pages"
                )
                .sheet(isPresented: $generateSheet) {
                    WikiGenerateSheet(storage: model.storage) { newPage in
                        model.upsert(newPage)
                        selectedPage = newPage
                        Task { await model.load() }
                    }
                }
                .navigationDestination(item: $selectedPage) { page in
                    WikiPageView(
                        page: page,
                        storage: model.storage,
                        onDeleted: { id in
                            model.remove(pageID: id)
                            selectedPage = nil
                        },
                        onRegenerated: { newPage in
                            model.upsert(newPage)
                            selectedPage = newPage
                        }
                    )
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.recentPages.isEmpty {
            loadingView
        } else if model.recentPages.isEmpty {
            emptyView
        } else if model.filteredPages.isEmpty {
            noResultsView
        } else {
            list
        }
    }

    // MARK: - Subviews

    private var list: some View {
        List {
            if let error = model.loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.groupedPages, id: \.bucket) { group in
                Section {
                    ForEach(group.pages, id: \.id) { page in
                        Button {
                            selectedPage = page
                        } label: {
                            WikiHomeRow(page: page)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(group.bucket.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(paperBackground)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading wiki…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paperBackground)
    }

    private var emptyView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No wiki pages yet.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("Tap + to generate your first page from a topic.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                generateSheet = true
            } label: {
                Label("Compile a page", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paperBackground)
    }

    private var noResultsView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No pages match \u{201C}\(model.searchQuery)\u{201D}")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paperBackground)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                generateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Compile a page")
        }
    }

    private var paperBackground: some View {
        // UX-04 §4 — paper, not glass. Warm off-white in light, warm
        // near-black in dark.
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.059, blue: 0.071, alpha: 1)
                : UIColor(red: 0.965, green: 0.949, blue: 0.914, alpha: 1)
        })
        .ignoresSafeArea()
    }
}

// MARK: - Row

private struct WikiHomeRow: View {
    let page: WikiPage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            confidenceMargin
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(page.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(page.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                if !page.summary.isEmpty {
                    Text(page.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label("\(citationCount)", systemImage: "quote.bubble")
                        .labelStyle(.titleAndIcon)
                    Text("\u{00B7}")
                    Text(WikiHomeRow.relativeFormatter.localizedString(
                        for: page.generatedAt,
                        relativeTo: Date()
                    ))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title), \(page.kind.displayName) page, \(citationCount) citations")
    }

    private var citationCount: Int {
        page.allClaims.reduce(0) { $0 + $1.citations.count }
    }

    /// Two-pixel margin rule keyed to the page's confidence, per UX-04 §4.
    private var confidenceMargin: some View {
        Rectangle()
            .fill(confidenceColor)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }

    private var confidenceColor: Color {
        switch page.confidence {
        case 0.66...: Color(red: 0.18, green: 0.55, blue: 0.34)
        case 0.33..<0.66: Color(red: 0.78, green: 0.55, blue: 0.10)
        default: Color(red: 0.78, green: 0.18, blue: 0.30)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
