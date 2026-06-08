import SwiftUI

struct AgentScheduledTasksView: View {
    @Environment(AppStateStore.self) private var store

    @State private var showCreate = false
    @State private var editingTask: AgentTaskSummary? = nil

    private var sortedTasks: [AgentTaskSummary] {
        store.scheduledTasks.sorted { lhs, rhs in
            switch (lhs.nextRunAt, rhs.nextRunAt) {
            case let (l?, r?): return l == r ? lhs.title < rhs.title : l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.title < rhs.title
            }
        }
    }

    var body: some View {
        List {
            if sortedTasks.isEmpty {
                emptyState
            } else {
                taskRows
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCreate) {
            AgentScheduledTaskFormSheet(mode: .create) { title, prompt, schedule in
                store.createScheduledPromptTask(title: title, prompt: prompt, schedule: schedule)
            }
        }
        .sheet(item: $editingTask) { task in
            AgentScheduledTaskFormSheet(mode: .edit(task)) { title, prompt, schedule in
                store.updateScheduledPromptTask(
                    id: task.id,
                    title: title,
                    prompt: prompt,
                    schedule: schedule
                )
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No scheduled tasks", systemImage: "calendar.badge.clock")
        } description: {
            Text("Ask your agent to schedule a recurring task, or tap + to create one.")
        } actions: {
            Button("Add Task") { showCreate = true }
                .buttonStyle(.glassProminent)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var taskRows: some View {
        ForEach(sortedTasks) { task in
            TaskRow(task: task)
                .contentShape(Rectangle())
                .onTapGesture {
                    if task.isPromptTask {
                        editingTask = task
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Run") {
                        store.runScheduledTaskNow(id: task.id)
                        Haptics.selection()
                    }
                    .tint(.teal)

                    if task.isPromptTask {
                        Button("Edit") { editingTask = task }
                            .tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        store.removeScheduledTask(id: task.id)
                        Haptics.selection()
                    }
                    Button(task.isEnabled ? "Disable" : "Enable") {
                        store.setScheduledTaskEnabled(id: task.id, isEnabled: !task.isEnabled)
                        Haptics.selection()
                    }
                    .tint(task.isEnabled ? .orange : .green)
                }
                .contextMenu {
                    Button("Run Now") { store.runScheduledTaskNow(id: task.id) }
                    if task.isPromptTask {
                        Button("Edit") { editingTask = task }
                    }
                    Button(task.isEnabled ? "Disable" : "Enable") {
                        store.setScheduledTaskEnabled(id: task.id, isEnabled: !task.isEnabled)
                    }
                    Button("Delete", role: .destructive) {
                        store.removeScheduledTask(id: task.id)
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showCreate = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }
        }
    }

    private struct TaskRow: View {
        let task: AgentTaskSummary

        var body: some View {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .top) {
                    Image(systemName: iconName)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(task.isEnabled ? .teal : .secondary)
                        .padding(.top, 2)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(AppTheme.Typography.callout.weight(.medium))

                        Text(detailText)
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    Label(scheduleLabel, systemImage: "repeat")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.teal)
                        .padding(.horizontal, AppTheme.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(Color.teal.opacity(0.10), in: Capsule())

                    Text(nextRunLabel)
                        .font(AppTheme.Typography.mono)
                        .foregroundStyle(.tertiary)

                    Text(task.status.capitalized)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(statusTint)
                }
                .padding(.leading, 18)
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }

        private var iconName: String {
            task.isPromptTask ? "text.bubble" : "calendar.badge.clock"
        }

        private var detailText: String {
            task.intentDetail ?? task.intentLabel ?? task.description ?? "Scheduled agent task"
        }

        private var scheduleLabel: String {
            switch task.schedule {
            case "hourly": return "Hourly"
            case "daily": return "Daily"
            case "nightly": return "Nightly"
            case "weekly": return "Weekly"
            case "once": return "Once"
            default:
                if let seconds = secondsFromCustomSchedule(task.schedule) {
                    return "Every \(seconds)s"
                }
                return task.schedule
            }
        }

        private var nextRunLabel: String {
            guard task.isEnabled else { return "Disabled" }
            guard let nextRunAt = task.nextRunAt else { return "No next run" }
            let date = Date(timeIntervalSince1970: TimeInterval(nextRunAt))
            let interval = date.timeIntervalSince(Date())
            guard interval > 0 else { return "Due now" }
            if interval < 3_600 { return "Next: in \(max(1, Int(interval / 60)))m" }
            if interval < 86_400 { return "Next: in \(max(1, Int(interval / 3_600)))h" }
            return "Next: in \(max(1, Int(interval / 86_400)))d"
        }

        private var statusTint: Color {
            switch task.status {
            case "failed": return .red
            case "running": return .orange
            case "completed": return .green
            default: return .secondary
            }
        }

        private func secondsFromCustomSchedule(_ schedule: String) -> Int? {
            guard schedule.hasPrefix("every "), schedule.hasSuffix("s") else { return nil }
            let start = schedule.index(schedule.startIndex, offsetBy: 6)
            let end = schedule.index(before: schedule.endIndex)
            return Int(schedule[start..<end])
        }
    }
}

private extension AgentTaskSummary {
    var isPromptTask: Bool {
        intentType == "agent_prompt"
    }
}
