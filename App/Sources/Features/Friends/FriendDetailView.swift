import SwiftUI

struct FriendDetailView: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Point size for the navigation chevron in the task list rows.
        static let chevronIconSize: CGFloat = 11
    }

    @Environment(AppStateStore.self) private var store
    let friend: Friend
    @State private var showRenameAlert = false
    @State private var newName = ""
    @State private var showCopiedFeedback = false
    @State private var showAddNote = false
    @State private var editingNote: Note? = nil
    @State private var selectedItemID: UUID? = nil
    @State private var showAddTask = false
    @State private var newTaskDraft = ""
    @FocusState private var taskFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNS

    private var currentFriend: Friend {
        store.friend(id: friend.id) ?? friend
    }

    private var friendItems: [Item] {
        let candidates = store.state.items
            .filter { !$0.deleted && $0.requestedByFriendID == friend.id }
        // Pending items honour the user-defined drag order (same as Home with
        // the .friend filter); completed items follow by completion date.
        let pending = store.state.sortedPendingItems(candidates.filter { $0.status == .pending })
        let done = candidates.filter { $0.status != .pending }.sorted { $0.updatedAt > $1.updatedAt }
        return pending + done
    }

    /// Notes about this friend — either attached directly to the friend
    /// (Anchor.friend) or attached to one of their requested items (Anchor.item).
    private var friendNotes: [Note] {
        let itemIDs = Set(friendItems.map(\.id))
        return store.activeNotes
            .filter { note in
                guard let target = note.target else { return false }
                switch target {
                case .friend(let id):   return id == friend.id
                case .item(let id):     return itemIDs.contains(id)
                case .note:             return false
                }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var addedDateString: String {
        "Friends since " + currentFriend.addedAt.formatted(.dateTime.month(.wide).year())
    }

    @ViewBuilder
    private func itemMetaRow(_ item: Item) -> some View {
        let isOverdue = item.isOverdue
        let isDueToday = !isOverdue && item.dueAt.map { Calendar.current.isDateInToday($0) } ?? false
        if isOverdue || isDueToday || item.dueAt != nil || item.isPriority {
            HStack(spacing: AppTheme.Spacing.xs) {
                if isOverdue {
                    Label("Overdue", systemImage: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(.red)
                } else if let due = item.dueAt {
                    Label("Due \(due.relativeDueLabel)", systemImage: isDueToday ? "clock.badge.fill" : "clock")
                        .foregroundStyle(isDueToday ? .orange : .secondary)
                }
                if item.isPriority {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Priority")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .labelStyle(.titleAndIcon)
        }
    }

    var body: some View {
        List {
            // Glass profile header — clear listRowBackground so glass renders properly
            Section {
                profileHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(AppTheme.Layout.cardRowInsetsSM)
            }

            Section("Tasks from \(currentFriend.displayName)") {
                    ForEach(friendItems) { item in
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.status == .done ? .green : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text(item.title)
                                    .strikethrough(item.status == .done)
                                    .foregroundStyle(item.status == .done ? .secondary : .primary)
                                    .lineLimit(2)
                                if item.status != .done {
                                    itemMetaRow(item)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: Layout.chevronIconSize, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .font(AppTheme.Typography.callout)
                        .opacity(item.status == .done ? 0.55 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.selection()
                            selectedItemID = item.id
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                let newStatus: ItemStatus = item.status == .done ? .pending : .done
                                store.setItemStatus(item.id, status: newStatus)
                                Haptics.success()
                            } label: {
                                Label(
                                    item.status == .done ? "Pending" : "Done",
                                    systemImage: item.status == .done ? "circle" : "checkmark.circle"
                                )
                            }
                            .tint(item.status == .done ? .orange : .green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                store.toggleItemPriority(item.id)
                                Haptics.selection()
                            } label: {
                                Label(
                                    item.isPriority ? "Unprioritize" : "Priority",
                                    systemImage: item.isPriority ? "star.slash" : "star.fill"
                                )
                            }
                            .tint(.orange)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item.status == .done ? "Done" : "Pending")
                        .accessibilityHint("Opens item detail")
                        .accessibilityAddTraits(.isButton)
                    }
                    if showAddTask {
                        addTaskRow
                    } else {
                        Button {
                            showAddTask = true
                            taskFieldFocused = true
                            Haptics.selection()
                        } label: {
                            Label("Add a task for \(currentFriend.displayName)…", systemImage: "plus.circle")
                                .font(AppTheme.Typography.callout)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

            Section {
                if friendNotes.isEmpty {
                    notesEmptyCTA
                } else {
                    ForEach(friendNotes) { note in
                        NoteListRow(
                            note: note,
                            onEdit: { editingNote = note },
                            onDelete: { store.deleteNote(note.id); Haptics.delete() }
                        )
                    }
                }
            } header: {
                NotesSectionHeader(title: "Notes", count: friendNotes.count, onAdd: { showAddNote = true })
            }

            Section {
                Button("Rename") {
                    newName = currentFriend.displayName
                    showRenameAlert = true
                }
            }

            Section {
                Button("Remove Friend", role: .destructive) {
                    store.removeFriend(friend.id)
                    Haptics.delete()
                    dismiss()
                }
            }
        }
        .navigationTitle(currentFriend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddNote = true
                } label: {
                    Label("Add note", systemImage: "square.and.pencil")
                }
            }
        }
        .alert("Rename Friend", isPresented: $showRenameAlert) {
            TextField("Display Name", text: $newName)
            Button("Save") {
                let t = newName.trimmed
                guard !t.isEmpty else { return }
                store.updateFriendDisplayName(friend.id, newName: t)
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddNote) {
            EditTextSheet(title: "Note about \(currentFriend.displayName)", initialText: "") { text in
                store.addNote(text: text, kind: .free, target: .friend(id: friend.id))
                Haptics.success()
            }
        }
        .sheet(item: $editingNote) { note in
            EditTextSheet(title: "Edit Note", initialText: note.text) { newText in
                var updated = note
                updated.text = newText
                store.updateNote(updated)
            }
        }
        .sheet(item: $selectedItemID) { id in
            ItemDetailSheet(itemID: id)
        }
    }

    // MARK: - Task quick-add helpers

    private var addTaskRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField("New task for \(currentFriend.displayName)…", text: $newTaskDraft)
                .focused($taskFieldFocused)
                .onSubmit { commitTask() }
                .submitLabel(.done)
            if !newTaskDraft.isBlank {
                Button(action: commitTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save task")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .font(AppTheme.Typography.callout)
        .animation(AppTheme.Animation.springFast, value: newTaskDraft.isBlank)
    }

    private func commitTask() {
        let trimmed = newTaskDraft.trimmed
        guard !trimmed.isEmpty else { showAddTask = false; return }
        store.addItem(
            title: trimmed,
            source: .manual,
            friendID: friend.id,
            friendName: currentFriend.displayName
        )
        Haptics.success()
        newTaskDraft = ""
        showAddTask = false
    }

    // MARK: - Notes section helpers

    private var notesEmptyCTA: some View {
        Button {
            showAddNote = true
        } label: {
            Label("Add a note about \(currentFriend.displayName)…", systemImage: "plus.circle")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Profile header

    private var taskCompletionBar: some View {
        let total = friendItems.count
        let done = friendItems.filter { $0.status != .pending }.count
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 4)
                Capsule()
                    .fill(fraction >= 1 ? Color.green : Color.accentColor)
                    .frame(width: max(4, geo.size.width * fraction), height: 4)
                    .animation(AppTheme.Animation.spring, value: fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var taskStatLine: some View {
        let total = friendItems.count
        let pending = friendItems.filter { $0.status == .pending }.count
        let label = pending > 0
            ? "\(total) task\(total == 1 ? "" : "s") · \(pending) pending"
            : "\(total) task\(total == 1 ? "" : "s") · all done"
        return Text(label)
            .font(AppTheme.Typography.caption)
            .foregroundStyle(pending > 0 ? Color.accentColor.opacity(0.8) : Color.green.opacity(0.8))
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var profileHeader: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            FriendAvatar(friend: currentFriend, size: 68)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(currentFriend.displayName)
                    .font(AppTheme.Typography.title)

                Button {
                    copyToClipboard(currentFriend.identifier, isCopied: $showCopiedFeedback)
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        if showCopiedFeedback {
                            Label("Copied!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(currentFriend.identifier, systemImage: "doc.on.doc")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(AppTheme.Typography.mono)
                    .truncatedMiddle()
                    .contentTransition(.identity)
                }
                .buttonStyle(.plain)
                .animation(AppTheme.Animation.springFast, value: showCopiedFeedback)
                .accessibilityLabel(showCopiedFeedback ? "Identifier copied" : "Copy identifier")
                .accessibilityHint("Copies the friend's identifier to the clipboard")

                Text(addedDateString)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)

                if !friendItems.isEmpty {
                    taskStatLine
                    taskCompletionBar
                }

                if let about = currentFriend.about {
                    Text(about)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.md)
        .glassSurface(cornerRadius: AppTheme.Corner.xl)
        .glassEffectID("profile-\(friend.id)", in: glassNS)
    }
}
