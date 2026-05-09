import SwiftUI

// MARK: - LibraryView

/// Root of the Library tab. Subscriptions grid + filter chips + a
/// search-entry bar that *deep-links to the Ask tab* (this view does
/// not implement search itself; the action is delegated through
/// `onOpenSearch`).
///
/// **Lane 3 wiring caveats** (read at merge):
///
///   - The Library tab does not yet exist in `RootView`. The
///     orchestrator wires it in a later lane. Until then this view is
///     orphaned — it just needs to compile and look right in
///     SwiftUI previews / a one-off harness.
///   - `onOpenSearch` defaults to a no-op so the view is constructible
///     in isolation. The orchestrator passes a closure that flips the
///     selected `RootTab` to the Ask tab.
///   - The mock store is created internally by default; injection via
///     environment is supported so tests / Lane 2 swaps trivially.
///
/// **Glass usage in this file:**
///
///   - The filter rail is wrapped in a structural glass container.
///   - The search-entry bar is a structural glass capsule.
///   - All cards (`LibraryGridCell`) are matte.
struct LibraryView: View {

    /// Closure invoked when the user taps the search-entry bar.
    /// Defaults to a no-op so the view is constructible in any
    /// container; the real wiring is the orchestrator's job.
    var onOpenSearch: () -> Void = { Haptics.light() }

    @State private var store = LibraryMockStore()
    @State private var filter: LibraryFilter = .all
    @State private var showOPMLImporter: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    searchEntryBar
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.sm)

                    filterRailContainer
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.sm)

                    if filteredSubs.isEmpty {
                        emptyState
                            .padding(.top, AppTheme.Spacing.xl)
                    } else {
                        grid
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.top, AppTheme.Spacing.lg)
                            .padding(.bottom, AppTheme.Spacing.xl)
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar { toolbarContent }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationDestination(for: LibraryMockSubscription.self) { sub in
                ShowDetailView(store: store, subscription: sub)
            }
            .sheet(isPresented: $showOPMLImporter) {
                OPMLImportSheet(
                    store: store,
                    onDismiss: { showOPMLImporter = false }
                )
            }
        }
    }

    // MARK: - Filtered subs

    private var filteredSubs: [LibraryMockSubscription] {
        store.filteredSubscriptions(filter)
    }

    // MARK: - Search entry bar

    /// Tappable capsule that *opens the Ask tab*. Looks like a search
    /// field; behaves like a route. The lane brief is explicit: do not
    /// implement search here.
    private var searchEntryBar: some View {
        Button {
            Haptics.light()
            onOpenSearch()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Tint.agentSurface)
                Text("Ask anything across your library…")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Corner.lg))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask anything across your library")
        .accessibilityHint("Opens the Ask tab")
    }

    // MARK: - Filter rail

    private var filterRailContainer: some View {
        LibraryFilterRail(selection: $filter)
            .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.lg) {
            ForEach(filteredSubs) { sub in
                NavigationLink(value: sub) {
                    LibraryGridCell(subscription: sub)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gridColumns: [GridItem] {
        // 3-up on iPhone (the spec); SwiftUI auto-flexes to 4 on iPad
        // since `GridItem.adaptive(minimum:)` reflows by available width.
        [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: AppTheme.Spacing.lg)]
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Your shows live here.")
                    .font(AppTheme.Typography.title)
                Text("Import from OPML or paste an RSS feed to begin.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Haptics.light()
                showOPMLImporter = true
            } label: {
                Label("Import from OPML", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Haptics.light()
                    showOPMLImporter = true
                } label: {
                    Label("Import OPML", systemImage: "square.and.arrow.down")
                }
                Button {
                    Haptics.light()
                    onOpenSearch()
                } label: {
                    Label("Ask the agent", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Add or ask")
        }
    }
}

// MARK: - Preview

#Preview {
    LibraryView()
}
