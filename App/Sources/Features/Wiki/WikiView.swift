import SwiftUI

// MARK: - Wiki home

/// Library-of-wikis home. Lists every page on disk, scoped by a Global /
/// per-podcast picker, and surfaces the "compile a new page" affordance
/// per UX-04 §3 (Information Architecture).
///
/// The view reads from an `WikiHomeViewModel`, which loads its inventory
/// from `WikiStorage`. When the storage is empty (typical in lane-7
/// stub mode) the model falls back to `WikiMockFixture.inventory` so the
/// home renders with editorial calm rather than a blank state.
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
                .sheet(isPresented: $generateSheet) {
                    WikiGenerateSheet(scope: model.scope) { newPage in
                        model.add(newPage)
                        selectedPage = newPage
                    }
                }
                .navigationDestination(item: $selectedPage) { page in
                    WikiPageView(page: page)
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.entries.isEmpty {
            empty
        } else {
            list
        }
    }

    // MARK: - Subviews

    private var list: some View {
        List {
            scopeSection
            Section {
                ForEach(model.entries, id: \.slug) { entry in
                    Button {
                        Task { await model.openPage(entry) { selectedPage = $0 } }
                    } label: {
                        WikiHomeRow(entry: entry)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("Pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(paperBackground)
    }

    private var empty: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Your wiki will appear as you listen.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("Compile a topic to start your library, or wait for the agent to refresh existing pages.")
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

    private var scopeSection: some View {
        Section {
            Picker("Scope", selection: $model.scope) {
                Text("Library").tag(WikiHomeViewModel.ScopeFilter.global)
                ForEach(model.podcastScopes, id: \.self) { scope in
                    Text(model.label(for: scope)).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                generateSheet = true
            } label: {
                Image(systemName: "wand.and.stars")
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
    let entry: WikiInventory.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            confidenceMargin
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(entry.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label("\(entry.citationCount)", systemImage: "quote.bubble")
                        .labelStyle(.titleAndIcon)
                    Text("·")
                    Text(WikiHomeRow.relativeFormatter.localizedString(
                        for: entry.generatedAt,
                        relativeTo: Date()
                    ))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(entry.kind.displayName) page, \(entry.citationCount) citations")
    }

    /// Two-pixel margin rule keyed to the page's confidence, per UX-04 §4.
    private var confidenceMargin: some View {
        Rectangle()
            .fill(confidenceColor)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }

    private var confidenceColor: Color {
        switch entry.confidence {
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
