import SwiftUI

struct UniversalSearchView: View {
    private enum Layout {
        static let iconSize: CGFloat = 48
    }

    private struct IdentifiedResult: Identifiable {
        let id: UUID
    }

    @Environment(AppStateStore.self) private var store
    @State private var query: String = ""
    @State private var selectedNoteID: UUID?
    @State private var selectedMemoryID: UUID?
    @State private var selectedItemID: UUID?

    private var itemResults: [Item] {
        guard !query.isBlank else { return [] }
        return store.activeItems
            .filter {
                $0.title.localizedCaseInsensitiveContains(query)
                || (!$0.details.isEmpty && $0.details.localizedCaseInsensitiveContains(query))
                || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var noteResults: [Note] {
        guard !query.isBlank else { return [] }
        return store.activeNotes
            .filter { $0.text.localizedCaseInsensitiveContains(query) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var memoryResults: [AgentMemory] {
        guard !query.isBlank else { return [] }
        return store.activeMemories
            .filter { $0.content.localizedCaseInsensitiveContains(query) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var totalCount: Int {
        itemResults.count + noteResults.count + memoryResults.count
    }

    var body: some View {
        List {
            if query.isBlank {
                emptyPrompt
            } else {
                if !itemResults.isEmpty {
                    Section("Items") {
                        ForEach(itemResults) { item in
                            Button {
                                selectedItemID = item.id
                                Haptics.selection()
                            } label: {
                                itemRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                UniversalSearchResults(
                    query: query,
                    noteResults: noteResults,
                    memoryResults: memoryResults,
                    onSelect: handleSelect
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Items, notes and memories...")
        .sheet(item: Binding(
            get: { selectedItemID.map(IdentifiedResult.init) },
            set: { selectedItemID = $0?.id }
        )) { identified in
            ItemDetailSheet(itemID: identified.id)
        }
        .sheet(item: Binding(
            get: { selectedNoteID.map(IdentifiedResult.init) },
            set: { selectedNoteID = $0?.id }
        )) { identified in
            NavigationStack {
                AgentNotesView(spotlightTargetID: identified.id)
                    .navigationTitle("Notes")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: Binding(
            get: { selectedMemoryID.map(IdentifiedResult.init) },
            set: { selectedMemoryID = $0?.id }
        )) { identified in
            NavigationStack {
                AgentMemoriesView(spotlightTargetID: identified.id)
                    .navigationTitle("Memories")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .toolbar {
            if !query.isBlank && totalCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(totalCount)")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(AppTheme.Animation.springFast, value: totalCount)
                }
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Layout.iconSize, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Search")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(.primary)

                Text("Find tasks, notes, and agent memories in one place.")
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AppTheme.Spacing.xs) {
                scopePill(icon: "checkmark.circle", label: "Items", color: .accentColor)
                scopePill(icon: "note.text", label: "Notes", color: .blue)
                scopePill(icon: "brain", label: "Memories", color: .purple)
            }
            .padding(.top, AppTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xl)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func itemRow(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
                HighlightedText(text: item.title, query: query)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.isOverdue {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .accessibilityLabel("Overdue")
                } else if item.isPriority {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Priority")
                }
            }
            if !item.details.isEmpty {
                HighlightedText(text: item.details, query: query)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !item.tags.isEmpty {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func scopePill(icon: String, label: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .font(AppTheme.Typography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func handleSelect(_ result: SearchResult) {
        Haptics.selection()
        switch result {
        case .note(let note):
            selectedNoteID = note.id
        case .memory(let memory):
            selectedMemoryID = memory.id
        }
    }
}
