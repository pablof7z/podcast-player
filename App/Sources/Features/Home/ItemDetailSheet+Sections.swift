import SwiftUI

// MARK: - ItemDetailSheet section builders

extension ItemDetailSheet {

    private enum Layout {
        static let metaIconWidth: CGFloat = 20
    }

    // MARK: - Notes section

    /// Notes attached directly to this item (Anchor.item).
    ///
    /// Mirrors the pattern in FriendDetailView — mutations (add/edit/delete) are
    /// applied to the store immediately and do NOT go through the sheet's Save gate.
    func notesSection(item: Item) -> some View {
        let itemNotes = store.activeNotes
            .filter { note in
                guard let target = note.target,
                      case .item(let id) = target else { return false }
                return id == item.id
            }
            .sorted { $0.createdAt > $1.createdAt }

        return Section {
            if itemNotes.isEmpty {
                Button {
                    showAddNote = true
                } label: {
                    Label("Add a note…", systemImage: "plus.circle")
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(itemNotes) { note in
                    NoteListRow(
                        note: note,
                        onEdit: { editingNote = note },
                        onDelete: { store.deleteNote(note.id); Haptics.delete() }
                    )
                }
            }
        } header: {
            NotesSectionHeader(title: "Notes", count: itemNotes.count, onAdd: { showAddNote = true })
        }
    }

    func dueDateSection(item: Item) -> some View {
        Section {
            Toggle(isOn: $dueDateEnabled.animation(AppTheme.Animation.springFast)) {
                Label("Due Date", systemImage: "calendar.badge.clock")
            }
            .onChange(of: dueDateEnabled) { _, enabled in
                if enabled && item.dueAt == nil {
                    // Default to tomorrow at midnight.
                    var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                    comps.day = (comps.day ?? 0) + 1
                    dueDate = Calendar.current.date(from: comps) ?? Date().addingTimeInterval(86_400)
                }
            }

            if dueDateEnabled {
                DatePicker(
                    "Date",
                    selection: $dueDate,
                    displayedComponents: [.date]
                )
                if item.isOverdue {
                    Label("This item is overdue", systemImage: "clock.badge.exclamationmark.fill")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Due Date")
        } footer: {
            Text("Marks the item overdue when the date passes. Independent of reminders.")
        }
    }

    // MARK: - Estimated Duration section

    /// Available preset durations, in minutes.
    private static let durationPresets: [Int] = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    func estimatedDurationSection(item: Item) -> some View {
        Section {
            Toggle(isOn: $estimatedMinutesEnabled.animation(AppTheme.Animation.springFast)) {
                Label("Estimated Duration", systemImage: "clock")
            }
            .onChange(of: estimatedMinutesEnabled) { _, enabled in
                if enabled && (item.estimatedMinutes ?? 0) == 0 {
                    estimatedMinutes = 30
                }
            }

            if estimatedMinutesEnabled {
                Picker("Duration", selection: $estimatedMinutes) {
                    ForEach(ItemDetailSheet.durationPresets, id: \.self) { mins in
                        Text(durationLabel(mins)).tag(mins)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Estimate")
        } footer: {
            if estimatedMinutesEnabled {
                Text("Shown as a time chip on the task row so you can plan your day.")
            } else {
                Text("How long do you think this will take?")
            }
        }
    }

    /// Formats a minutes count into a human-readable label for the picker.
    private func durationLabel(_ mins: Int) -> String {
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    func reminderSection(item: Item) -> some View {
        Section {
            Toggle(isOn: $reminderEnabled.animation(AppTheme.Animation.springFast)) {
                Label("Reminder", systemImage: "bell")
            }
            .onChange(of: reminderEnabled) { _, enabled in
                if enabled && item.reminderAt == nil {
                    // Default to 1 hour from now, rounded to the next hour.
                    var comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: Date())
                    comps.hour = (comps.hour ?? 0) + 1
                    comps.minute = 0
                    reminderDate = Calendar.current.date(from: comps) ?? Date().addingTimeInterval(3_600)
                }
                if !enabled { reminderRecurrence = .none }
            }

            if reminderEnabled {
                DatePicker(
                    "Date & Time",
                    selection: $reminderDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Picker("Repeat", selection: $reminderRecurrence) {
                    ForEach(ItemRecurrence.allCases, id: \.self) { recurrence in
                        Text(recurrence.label).tag(recurrence)
                    }
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            if reminderEnabled && reminderRecurrence != .none {
                Text("Repeats \(reminderRecurrence.label.lowercased()) at the selected time.")
            }
        }
    }

    func metadataSection(item: Item) -> some View {
        Section("Info") {
            metaRow(
                icon: "calendar",
                tint: .secondary,
                label: "Created",
                value: item.createdAt.shortDateTime
            )
            if item.status == .done {
                metaRow(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    label: "Completed",
                    value: RelativeTimestamp.extended(item.updatedAt)
                )
            } else if item.updatedAt.timeIntervalSince(item.createdAt) > 60 {
                metaRow(
                    icon: "pencil.and.clock",
                    tint: .secondary,
                    label: "Updated",
                    value: RelativeTimestamp.extended(item.updatedAt)
                )
            }
            if item.source != .manual {
                metaRow(
                    icon: item.source == .agent ? "sparkles" : "mic",
                    tint: item.source == .agent ? .purple : .blue,
                    label: "Added via",
                    value: item.source == .agent ? "Agent" : "Voice"
                )
            }
            if let name = item.requestedByDisplayName {
                metaRow(
                    icon: "person.fill",
                    tint: .teal,
                    label: "Requested by",
                    value: name
                )
            }
        }
    }

    func actionsSection(item: Item) -> some View {
        Section("Actions") {
            Button {
                commitEdits()
                let newStatus: ItemStatus = item.status == .done ? .pending : .done
                store.setItemStatus(itemID, status: newStatus)
                dismiss()
            } label: {
                Label(
                    item.status == .done ? "Mark as Pending" : "Mark as Done",
                    systemImage: item.status == .done ? "circle" : "checkmark.circle"
                )
            }

            Button {
                store.toggleItemPriority(itemID)
                Haptics.selection()
            } label: {
                Label(
                    item.isPriority ? "Remove Priority" : "Mark as Priority",
                    systemImage: item.isPriority ? "star.slash" : "star.fill"
                )
            }
            .foregroundStyle(.orange)
            // ⌘P — toggle priority flag (iPad / hardware keyboard)
            .keyboardShortcut("p", modifiers: .command)

            Button {
                store.toggleItemPin(itemID)
                Haptics.selection()
            } label: {
                Label(
                    item.isPinned ? "Unpin" : "Pin to Top",
                    systemImage: item.isPinned ? "pin.slash" : "pin.fill"
                )
            }
            .foregroundStyle(Color.accentColor)

            ShareLink(item: shareText(for: item)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Item", systemImage: "trash")
            }
        }
    }

    private func shareText(for item: Item) -> String {
        var parts = [item.title]
        if !item.details.isEmpty { parts.append(item.details) }
        if let due = item.dueAt { parts.append("Due: \(due.relativeDueLabel)") }
        return parts.joined(separator: "\n")
    }

    // MARK: - Meta row helper

    func metaRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: Layout.metaIconWidth)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(AppTheme.Typography.subheadline)
    }
}
