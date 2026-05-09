import SwiftUI

// MARK: - Context menu

extension HomeItemRow {

    @ViewBuilder
    var contextMenuItems: some View {
        Button {
            onToggle()
        } label: {
            Label(
                item.status == .done ? "Mark as Pending" : "Mark as Done",
                systemImage: item.status == .done ? "circle" : "checkmark.circle"
            )
        }

        Button {
            onTogglePriority()
        } label: {
            Label(
                item.isPriority ? "Remove Priority" : "Mark as Priority",
                systemImage: item.isPriority ? "star.slash" : "star"
            )
        }

        if let onTogglePin {
            Button {
                onTogglePin()
            } label: {
                Label(
                    item.isPinned ? "Unpin" : "Pin to Top",
                    systemImage: item.isPinned ? "pin.slash" : "pin"
                )
            }
        }

        if let onSetDueDate {
            Divider()
            dueDateSubmenu(onSetDueDate: onSetDueDate)
        }

        if let onSetColorTag {
            colorTagSubmenu(onSetColorTag: onSetColorTag)
        }

        if let onSetDuration {
            durationSubmenu(onSetDuration: onSetDuration)
        }

        if let onDuplicate {
            Divider()
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }

        Divider()

        ShareLink(item: shareText) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var shareText: String {
        var lines: [String] = [item.title]
        if !item.details.isEmpty {
            lines.append(item.details)
        }
        if let due = item.dueAt {
            let label = item.isOverdue ? "Overdue · \(due.shortDate)" : "Due \(due.shortDate)"
            lines.append(label)
        }
        if let friend = item.requestedByDisplayName {
            lines.append("From \(friend)")
        }
        if !item.tags.isEmpty {
            lines.append(item.tags.map { "#\($0)" }.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    private func colorTagSubmenu(onSetColorTag: @escaping (ItemColorTag) -> Void) -> some View {
        Menu {
            ForEach(ItemColorTag.allCases, id: \.self) { colorTag in
                Button {
                    onSetColorTag(colorTag)
                } label: {
                    HStack {
                        if colorTag == .none {
                            Label(colorTag.label, systemImage: "circle.slash")
                        } else {
                            Label(colorTag.label, systemImage: "circle.fill")
                        }
                        if item.colorTag == colorTag {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .tint(colorTag == .none ? Color.secondary : colorTag.color)
            }
        } label: {
            Label("Color", systemImage: item.colorTag == .none ? "circle.slash" : "circle.fill")
        }
    }

    private func dueDateSubmenu(onSetDueDate: @escaping (Date?) -> Void) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        // "This Week" lands on Friday — a more useful working-week deadline than Sunday.
        let endOfWeek: Date = {
            if let interval = cal.dateInterval(of: .weekOfYear, for: today) {
                return cal.date(byAdding: .day, value: -2, to: interval.end) ?? tomorrow
            }
            return cal.date(byAdding: .day, value: 5, to: today) ?? tomorrow
        }()

        return Menu {
            Button { onSetDueDate(today) } label: { Label("Today", systemImage: "calendar") }
            Button { onSetDueDate(tomorrow) } label: { Label("Tomorrow", systemImage: "calendar.badge.plus") }
            Button { onSetDueDate(endOfWeek) } label: { Label("This Week", systemImage: "calendar.badge.clock") }
            if item.dueAt != nil {
                Divider()
                Button(role: .destructive) { onSetDueDate(nil) } label: {
                    Label("Clear Due Date", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            Label("Set Due Date", systemImage: "calendar")
        }
    }

    private func durationSubmenu(onSetDuration: @escaping (Int?) -> Void) -> some View {
        Menu {
            Button { onSetDuration(15) } label: { Label("15 min", systemImage: "clock") }
            Button { onSetDuration(30) } label: { Label("30 min", systemImage: "clock") }
            Button { onSetDuration(60) } label: { Label("1 hour", systemImage: "clock") }
            Button { onSetDuration(120) } label: { Label("2 hours", systemImage: "clock") }
            if item.estimatedMinutes != nil {
                Divider()
                Button(role: .destructive) { onSetDuration(nil) } label: {
                    Label("Clear Duration", systemImage: "clock.badge.xmark")
                }
            }
        } label: {
            Label(
                item.estimatedMinutes != nil ? "Change Duration" : "Set Duration",
                systemImage: "clock"
            )
        }
    }
}
