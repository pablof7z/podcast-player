import SwiftUI

// MARK: - FeedbackView

struct FeedbackView: View {
    @Bindable var workflow: FeedbackWorkflow
    @Environment(\.dismiss) private var dismiss

    @State private var store = FeedbackStore()
    @State private var composerPresented = false
    @State private var showMine = true
    @State private var identityPresented = false
    @State private var searchText = ""

    private var visibleThreads: [FeedbackThread] {
        // Both segments return all threads until identity / multi-user is wired up.
        guard !searchText.isBlank else {
            return store.threads
        }
        let query = searchText.lowercased()
        return store.threads.filter { thread in
            (thread.title ?? "").lowercased().contains(query)
            || thread.content.lowercased().contains(query)
            || (thread.summary ?? "").lowercased().contains(query)
            || thread.category.rawValue.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Feedback")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search feedback")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarButtons
                    }
                }
        }
        .task { await store.load() }
        .sheet(isPresented: $composerPresented) {
            FeedbackComposeView(store: store, workflow: workflow)
        }
        .sheet(isPresented: $identityPresented) {
            UserIdentityView()
        }
        .onAppear {
            if workflow.screenshot != nil || workflow.annotatedImage != nil {
                composerPresented = true
            }
        }
    }

    // MARK: - Trailing toolbar

    @ViewBuilder
    private var trailingToolbarButtons: some View {
        GlassEffectContainer(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    identityPresented = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Identity")
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                Button {
                    composerPresented = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New feedback")
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.threads.isEmpty {
            loadingSkeleton
        } else if store.threads.isEmpty {
            emptyState
        } else if visibleThreads.isEmpty {
            noSearchResults
        } else {
            threadList
        }
    }

    // MARK: - Thread list

    @ViewBuilder
    private var threadList: some View {
        List {
            mineEveryoneSegmentedControl
                .listRowBackground(Color.clear)
                .listRowInsets(AppTheme.Layout.cardRowInsetsSM)
                .listRowSeparator(.hidden)

            ForEach(visibleThreads) { thread in
                NavigationLink {
                    FeedbackThreadDetailView(thread: thread, store: store)
                } label: {
                    FeedbackThreadRow(thread: thread, query: searchText)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Haptics.warning()
                        store.deleteThread(id: thread.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.load() }
    }

    // MARK: - Segmented control

    @ViewBuilder
    private var mineEveryoneSegmentedControl: some View {
        Picker("Show", selection: $showMine) {
            Text("Mine").tag(true)
            Text("Everyone").tag(false)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Loading skeleton

    @ViewBuilder
    private var loadingSkeleton: some View {
        List {
            ForEach(0..<3, id: \.self) { _ in
                FeedbackThreadRow(thread: Self.placeholderThread)
                    .redacted(reason: .placeholder)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private static var placeholderThread: FeedbackThread {
        FeedbackThread(
            category: .bug,
            content: "This is a placeholder feedback item for skeleton loading state.",
            title: "Placeholder thread title here",
            summary: "Short summary of the thread for preview purposes."
        )
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No feedback yet", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Tap the pencil to share your thoughts.")
        }
    }

    // MARK: - No search results

    @ViewBuilder
    private var noSearchResults: some View {
        ContentUnavailableView.search(text: searchText)
    }

}

