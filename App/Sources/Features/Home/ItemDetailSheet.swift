import SwiftUI

// MARK: - ItemDetailSheet

/// Modal detail sheet for a single item.
///
/// Surfaces `item.details` and `item.reminderAt` — two fields the agent can
/// write that previously had no UI representation — and lets the user edit
/// them directly without going through the agent.
///
/// Opened by tapping any `HomeItemRow` in `HomeView`.
struct ItemDetailSheet: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Minimum height for the details TextEditor.
        static let detailsMinHeight: CGFloat = 80
        /// Icon size for the due-date chip calendar symbol.
        static let chipIconSize: CGFloat = 13
        /// Soft character limit for the details field. Exceeding it turns the
        /// count label red but does not block input.
        static let detailsCharacterLimit: Int = 500
    }

    // MARK: - Input

    let itemID: UUID

    // MARK: - Environment

    @Environment(AppStateStore.self) var store
    @Environment(\.dismiss) var dismiss

    // MARK: - State

    @State private var titleDraft: String = ""
    @State private var detailsDraft: String = ""
    @State var reminderDate: Date = Date()
    @State var reminderEnabled: Bool = false
    @State var reminderRecurrence: ItemRecurrence = .none
    @State var dueDate: Date = Date()
    @State var dueDateEnabled: Bool = false
    @State var showDeleteConfirm = false
    @State private var isSavingReminder = false
    @State var showAddNote = false
    @State var editingNote: Note? = nil
    @State private var showDueDatePopover = false
    @State private var showDurationPopover = false
    @FocusState private var titleFocused: Bool
    /// Whether the user has enabled an estimated duration for this item.
    @State var estimatedMinutesEnabled: Bool = false
    /// The current estimate value in minutes, used when `estimatedMinutesEnabled` is `true`.
    @State var estimatedMinutes: Int = 30

    // MARK: - Derived

    private var item: Item? {
        store.item(id: itemID)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                if let item {
                    content(for: item)
                } else {
                    // Item was deleted while the sheet was open.
                    Text("Item not found")
                        .foregroundStyle(.secondary)
                        .onAppear { dismiss() }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .alert("Delete Item?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let item { deleteItem(item) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the item.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { populateDrafts() }
        .sheet(isPresented: $showAddNote) {
            EditTextSheet(title: "Add Note", initialText: "") { text in
                store.addNote(text: text, kind: .free, target: .item(id: itemID))
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
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                commitEdits()
                dismiss()
            }
            .fontWeight(.semibold)
            .disabled(!hasChanges)
            // ⌘S — save changes (iPad / hardware keyboard)
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    // MARK: - Main content

    private func content(for item: Item) -> some View {
        List {
            titleSection
            dueDateChipSection(item: item)
            durationChipSection(item: item)
            detailsSection
            notesSection(item: item)
            ItemDetailTagsSection(item: item)
            ItemDetailColorSection(item: item)
            dueDateSection(item: item)
            estimatedDurationSection(item: item)
            reminderSection(item: item)
            metadataSection(item: item)
            actionsSection(item: item)
        }
        .settingsListStyle()
    }

    // MARK: - Sections

    /// A compact due-date chip displayed just below the title field for quick
    /// at-a-glance access. Tapping opens a popover `DatePicker` so the user can
    /// change the date without scrolling to the Due Date section below.
    ///
    /// The chip stays in sync with the `dueDateEnabled` / `dueDate` state that
    /// the full Due Date section also writes to, so both controls are always
    /// consistent and changes flow through the same `commitEdits()` path.
    @ViewBuilder
    private func dueDateChipSection(item: Item) -> some View {
        Section {
            HStack(spacing: AppTheme.Spacing.sm) {
                // Chip — tappable to open the inline date popover.
                Button {
                    if !dueDateEnabled {
                        // Enable with a sensible default (tomorrow) before opening picker.
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                        comps.day = (comps.day ?? 0) + 1
                        dueDate = Calendar.current.date(from: comps) ?? Date().addingTimeInterval(86_400)
                        dueDateEnabled = true
                    }
                    showDueDatePopover = true
                    Haptics.selection()
                } label: {
                    dueDateChipLabel(item: item)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDueDatePopover, arrowEdge: .top) {
                    dueDatePickerPopover
                }
                .accessibilityLabel(dueDateEnabled ? "Due \(dueDate.shortDate). Tap to change." : "No due date. Tap to add.")
                .accessibilityHint("Opens an inline date picker")

                Spacer(minLength: 0)

                // Quick "clear" button shown only when a due date is set.
                if dueDateEnabled {
                    Button {
                        dueDateEnabled = false
                        Haptics.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(AppTheme.Typography.callout)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear due date")
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(AppTheme.Animation.springFast, value: dueDateEnabled)
            .listRowInsets(.init(
                top: AppTheme.Spacing.xs,
                leading: AppTheme.Spacing.md,
                bottom: AppTheme.Spacing.xs,
                trailing: AppTheme.Spacing.md
            ))
        }
    }

    /// Label content for the due-date chip — adapts to whether a date is set,
    /// and whether the item is overdue.
    @ViewBuilder
    private func dueDateChipLabel(item: Item) -> some View {
        let isOverdue = dueDateEnabled && item.isOverdue
        let chipColor: Color = isOverdue ? .red : (dueDateEnabled ? .accentColor : .secondary)

        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: isOverdue
                  ? "clock.badge.exclamationmark.fill"
                  : (dueDateEnabled ? "calendar.badge.checkmark" : "calendar.badge.plus"))
                .font(.system(size: Layout.chipIconSize, weight: .medium))
                .foregroundStyle(chipColor)
                .accessibilityHidden(true)

            if dueDateEnabled {
                Text(isOverdue ? "Overdue · \(dueDate.relativeDueLabel)" : "Due \(dueDate.relativeDueLabel)")
                    .font(AppTheme.Typography.subheadline.weight(.medium))
                    .foregroundStyle(chipColor)
            } else {
                Text("Add due date")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(chipColor.opacity(0.10), in: Capsule())
        .contentShape(Capsule())
    }

    /// Popover content for the inline date picker. Uses `.graphical` style for a
    /// calendar grid that makes date picking spatial and quick.
    private var dueDatePickerPopover: some View {
        NavigationStack {
            DatePicker(
                "Due Date",
                selection: $dueDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .padding(AppTheme.Spacing.md)
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showDueDatePopover = false
                        Haptics.selection()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationCompactAdaptation(.popover)
    }

    /// Compact duration chip mirroring `dueDateChipSection` — shows "Add duration"
    /// or the formatted estimate (e.g. "30 min", "1h 30m") and opens a popover
    /// stepper on tap. Keeps the estimate visible without scrolling to the full section.
    @ViewBuilder
    private func durationChipSection(item: Item) -> some View {
        Section {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    if !estimatedMinutesEnabled {
                        estimatedMinutes = 30
                        estimatedMinutesEnabled = true
                    }
                    showDurationPopover = true
                    Haptics.selection()
                } label: {
                    durationChipLabel
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDurationPopover, arrowEdge: .top) {
                    durationPickerPopover
                }
                .accessibilityLabel(estimatedMinutesEnabled
                    ? "Duration \(durationDisplayLabel). Tap to change."
                    : "No duration set. Tap to add.")
                .accessibilityHint("Opens a duration picker")

                Spacer(minLength: 0)

                if estimatedMinutesEnabled {
                    Button {
                        estimatedMinutesEnabled = false
                        Haptics.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(AppTheme.Typography.callout)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear duration")
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(AppTheme.Animation.springFast, value: estimatedMinutesEnabled)
            .listRowInsets(.init(
                top: AppTheme.Spacing.xs,
                leading: AppTheme.Spacing.md,
                bottom: AppTheme.Spacing.xs,
                trailing: AppTheme.Spacing.md
            ))
        }
    }

    @ViewBuilder
    private var durationChipLabel: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: estimatedMinutesEnabled ? "clock.fill" : "clock.badge.plus")
                .font(.system(size: Layout.chipIconSize, weight: .medium))
                .foregroundStyle(estimatedMinutesEnabled ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            Text(estimatedMinutesEnabled ? durationDisplayLabel : "Add duration")
                .font(estimatedMinutesEnabled
                    ? AppTheme.Typography.subheadline.weight(.medium)
                    : AppTheme.Typography.subheadline)
                .foregroundStyle(estimatedMinutesEnabled ? Color.accentColor : .secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background((estimatedMinutesEnabled ? Color.accentColor : Color.secondary).opacity(0.10), in: Capsule())
        .contentShape(Capsule())
    }

    private var durationPickerPopover: some View {
        NavigationStack {
            Form {
                Stepper(value: $estimatedMinutes, in: 5...480, step: 5) {
                    Text(durationDisplayLabel)
                        .font(AppTheme.Typography.body)
                        .monospacedDigit()
                }
            }
            .navigationTitle("Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        estimatedMinutesEnabled = true
                        showDurationPopover = false
                        Haptics.selection()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationCompactAdaptation(.popover)
    }

    private var durationDisplayLabel: String {
        if estimatedMinutes < 60 { return "\(estimatedMinutes) min" }
        let h = estimatedMinutes / 60
        let m = estimatedMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private var titleSection: some View {
        Section("Title") {
            TextField("Title", text: $titleDraft, axis: .vertical)
                .font(AppTheme.Typography.body)
                .lineLimit(1...4)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { titleFocused = false }
        }
    }

    private var detailsSection: some View {
        Section {
            TextEditor(text: $detailsDraft)
                .font(AppTheme.Typography.body)
                .frame(minHeight: Layout.detailsMinHeight)
                .scrollContentBackground(.hidden)
        } header: {
            Text("Details")
        } footer: {
            HStack(alignment: .top) {
                Text("Optional notes your agent can also read and update.")
                Spacer(minLength: AppTheme.Spacing.sm)
                if !detailsDraft.isEmpty {
                    let count = detailsDraft.count
                    Text("\(count)/\(Layout.detailsCharacterLimit)")
                        .monospacedDigit()
                        .foregroundStyle(count > Layout.detailsCharacterLimit ? .red : .secondary)
                        .animation(AppTheme.Animation.springFast, value: count > Layout.detailsCharacterLimit)
                }
            }
        }
    }

    // MARK: - Logic

    private var hasChanges: Bool {
        guard let item else { return false }
        let titleChanged = titleDraft.trimmed != item.title
        let detailsChanged = detailsDraft.trimmed != item.details
        let reminderChanged = reminderEnabled != (item.reminderAt != nil) ||
            (reminderEnabled && abs(reminderDate.timeIntervalSince(item.reminderAt ?? Date())) > 60) ||
            (reminderEnabled && reminderRecurrence != item.recurrence)
        let dueDateChanged = dueDateEnabled != (item.dueAt != nil) ||
            (dueDateEnabled && abs(dueDate.timeIntervalSince(item.dueAt ?? Date())) > 60)
        let estimatedChanged = estimatedMinutesEnabled != (item.estimatedMinutes != nil) ||
            (estimatedMinutesEnabled && estimatedMinutes != (item.estimatedMinutes ?? 0))
        return titleChanged || detailsChanged || reminderChanged || dueDateChanged || estimatedChanged
    }

    private func populateDrafts() {
        guard let item else { return }
        titleDraft = item.title
        detailsDraft = item.details
        if let date = item.reminderAt {
            reminderEnabled = true
            reminderDate = date
        } else {
            reminderEnabled = false
        }
        reminderRecurrence = item.recurrence
        if let date = item.dueAt {
            dueDateEnabled = true
            dueDate = date
        } else {
            dueDateEnabled = false
        }
        if let mins = item.estimatedMinutes, mins > 0 {
            estimatedMinutesEnabled = true
            estimatedMinutes = mins
        } else {
            estimatedMinutesEnabled = false
            estimatedMinutes = 30
        }
    }

    func commitEdits() {
        guard var item else { return }

        let newTitle = titleDraft.trimmed
        let newDetails = detailsDraft.trimmed

        if !newTitle.isEmpty { item.title = newTitle }
        item.details = newDetails

        // Persist recurrence on the item.
        item.recurrence = reminderEnabled ? reminderRecurrence : .none

        store.updateItem(item)
        Haptics.success()

        // Handle reminder changes.
        if reminderEnabled {
            store.setReminderAt(itemID, date: reminderDate)
            Task {
                await NotificationService.scheduleReminder(
                    for: itemID,
                    title: item.title,
                    at: reminderDate,
                    recurrence: reminderRecurrence
                )
            }
        } else if item.reminderAt != nil {
            store.setReminderAt(itemID, date: nil)
            NotificationService.cancel(for: itemID)
        }

        // Handle due date changes.
        if dueDateEnabled {
            store.setDueDate(itemID, date: dueDate)
        } else if item.dueAt != nil {
            store.setDueDate(itemID, date: nil)
        }

        // Handle estimated duration changes.
        if estimatedMinutesEnabled && estimatedMinutes > 0 {
            store.setEstimatedMinutes(itemID, minutes: estimatedMinutes)
        } else if item.estimatedMinutes != nil {
            store.setEstimatedMinutes(itemID, minutes: nil)
        }
    }

    private func deleteItem(_ item: Item) {
        store.deleteItem(item.id)
        Haptics.selection()
        dismiss()
    }
}
