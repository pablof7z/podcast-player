import SwiftUI

// MARK: - CompletedItemsView

/// History screen for items that have been marked done.
///
/// Shows all `store.completedItems` grouped by relative-date bucket, with
/// swipe and context-menu actions for restoring to pending or permanently
/// deleting. Mirrors the structure of `AgentNotesView`.
struct CompletedItemsView: View {

    private enum Layout {
        static let chipHPadding: CGFloat = 10
        static let chipVPadding: CGFloat = 6
    }

    @Environment(AppStateStore.self) private var store
    @State private var searchText = ""
    @State private var showClearConfirm = false
    @State private var selectedTag: String?

    // MARK: - Derived

    private var availableTags: [String] {
        let all = store.completedItems.flatMap(\.tags)
        let unique = Array(Set(all)).sorted()
        return unique
    }

    private var filteredItems: [Item] {
        var items = store.completedItems
        if !searchText.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }
        if let tag = selectedTag {
            items = items.filter { $0.tags.contains(tag) }
        }
        return items
    }

    private var groupedItems: [(bucket: RelativeDateBucket, items: [Item])] {
        RelativeDateBucket.grouped(filteredItems, dateKey: \.updatedAt)
    }

    private var tagCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for item in store.completedItems {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Body

    var body: some View {
        List {
            if !availableTags.isEmpty {
                tagChipsSection
            }
            if filteredItems.isEmpty {
                emptyState
            } else {
                itemSections
            }
        }
        .navigationTitle("Completed")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search completed")
        .toolbar { toolbarContent }
        .alert("Clear All Completed?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) {
                store.clearCompletedItems()
                Haptics.bulkAction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All completed items will be permanently removed. This cannot be undone.")
        }
    }

    // MARK: - Subviews

    private var tagChipsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    chipButton(tag: nil, label: "All", count: store.completedItems.count)
                    ForEach(availableTags, id: \.self) { tag in
                        chipButton(tag: tag, label: tag, count: tagCounts[tag] ?? 0)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.xs)
            }
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .animation(AppTheme.Animation.springFast, value: selectedTag)
        }
    }

    private func chipButton(tag: String?, label: String, count: Int) -> some View {
        let isSelected = selectedTag == tag
        return Button {
            selectedTag = tag
            Haptics.selection()
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(label)
                    .font(AppTheme.Typography.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, Layout.chipHPadding)
            .padding(.vertical, Layout.chipVPadding)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(label), \(count) item\(count == 1 ? "" : "s")\(isSelected ? ", selected" : "")")
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView {
                Label("No completed items", systemImage: "checkmark.circle")
            } description: {
                Text("Items you mark as done will appear here.")
            }
            .listRowBackground(Color.clear)
        } else {
            ContentUnavailableView.search(text: searchText)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var itemSections: some View {
        ForEach(groupedItems, id: \.bucket) { group in
            Section {
                ForEach(group.items) { item in
                    completedItemRow(item)
                }
            } header: {
                HStack {
                    Text(group.bucket.rawValue)
                    Spacer()
                    Text("\(group.items.count)")
                        .monospacedDigit()
                }
            }
        }
    }

    private func completedItemRow(_ item: Item) -> some View {
        CompletedItemRow(item: item, query: searchText)
            .contextMenu {
                Button {
                    store.setItemStatus(item.id, status: .pending)
                    Haptics.success()
                } label: {
                    Label("Restore to Pending", systemImage: "arrow.uturn.backward.circle")
                }
                Button(role: .destructive) {
                    store.deleteItem(item.id)
                    Haptics.delete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    store.setItemStatus(item.id, status: .pending)
                    Haptics.success()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward.circle")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    store.deleteItem(item.id)
                    Haptics.delete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !store.completedItems.isEmpty {
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear All", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
    }

    // MARK: - CompletedItemRow

    private struct CompletedItemRow: View {

    private enum Layout {
        static let iconSize: CGFloat = 20
        static let stripeWidth: CGFloat = 3
        static let stripeCornerRadius: CGFloat = 2
    }

    let item: Item
    var query: String = ""

    /// Shows the actual time ("Done at 2:30 PM") for same-day completions so users
    /// get precise context without redundant relative-age noise in the "Today" bucket.
    /// Falls back to the standard relative timestamp for older items.
    private var completionTimeLabel: String {
        guard Calendar.current.isDateInToday(item.updatedAt) else {
            return RelativeTimestamp.extended(item.updatedAt)
        }
        return "Done at \(item.updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(spacing: 0) {
            colorStripe
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: Layout.iconSize))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Group {
                        if query.isEmpty {
                            Text(item.title)
                        } else {
                            HighlightedText(text: item.title, query: query)
                        }
                    }
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(.secondary)
                        .strikethrough(true, color: .secondary)
                        .lineLimit(2)

                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(completionTimeLabel)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.tertiary)

                        if item.source != .manual {
                            Label(
                                item.source == .agent ? "Agent" : "Voice",
                                systemImage: item.source == .agent ? "sparkles" : "mic"
                            )
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.tertiary)
                            .labelStyle(.titleAndIcon)
                        }

                        if let friendName = item.requestedByDisplayName {
                            Label(friendName, systemImage: "person.fill")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(.tertiary)
                                .labelStyle(.titleAndIcon)
                        }

                        if item.recurrence != .none {
                            Label("↻ \(item.recurrence.shortLabel)", systemImage: "arrow.clockwise")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(.tertiary)
                                .labelStyle(.titleOnly)
                        }
                    }

                    if !item.tags.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(AppTheme.Typography.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, AppTheme.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.10), in: Capsule())
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }

    @ViewBuilder
    private var colorStripe: some View {
        if item.colorTag != .none {
            RoundedRectangle(cornerRadius: Layout.stripeCornerRadius)
                .fill(item.colorTag.color)
                .frame(width: Layout.stripeWidth)
                .padding(.vertical, AppTheme.Spacing.xs + 2)
                .padding(.trailing, AppTheme.Spacing.xs)
                .accessibilityHidden(true)
        }
    }
    }
}
