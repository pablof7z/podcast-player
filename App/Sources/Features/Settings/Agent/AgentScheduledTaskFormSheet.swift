import SwiftUI

// MARK: - AgentScheduledTaskFormSheet

/// Modal form for creating or editing an `agent_prompt` task.
struct AgentScheduledTaskFormSheet: View {

    enum Mode {
        case create
        case edit(AgentTaskSummary)
    }

    private enum Preset {
        static let options: [(label: String, schedule: String)] = [
            ("Hourly", "hourly"),
            ("Daily", "daily"),
            ("Weekly", "weekly"),
            ("Once", "once"),
        ]
    }

    let mode: Mode
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var prompt: String = ""
    @State private var selectedSchedule = "daily"
    @State private var customSeconds: String = ""
    @State private var useCustom = false

    @FocusState private var promptFocused: Bool

    private var titleText: String {
        switch mode {
        case .create: return "New Task"
        case .edit:   return "Edit Task"
        }
    }

    private var resolvedSchedule: String? {
        if useCustom {
            guard let seconds = Int(customSeconds), seconds > 0 else { return nil }
            return "every \(seconds)s"
        }
        return selectedSchedule
    }

    private var saveDisabled: Bool {
        title.trimmed.isEmpty || prompt.trimmed.isEmpty || resolvedSchedule == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                promptSection
                scheduleSection
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commitSave() }
                        .disabled(saveDisabled)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { seedFromMode() }
    }

    private var titleSection: some View {
        Section("Title") {
            TextField("Short name for this task", text: $title)
                .font(AppTheme.Typography.body)
        }
    }

    private var promptSection: some View {
        Section {
            TextEditor(text: $prompt)
                .focused($promptFocused)
                .font(AppTheme.Typography.body)
                .frame(minHeight: 80)
        } header: {
            Text("Prompt")
        } footer: {
            Text("The agent will run this prompt on the schedule you choose.")
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            ForEach(Preset.options, id: \.schedule) { option in
                Button {
                    selectedSchedule = option.schedule
                    useCustom = false
                } label: {
                    HStack {
                        Text(option.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if !useCustom && selectedSchedule == option.schedule {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .font(AppTheme.Typography.caption.weight(.semibold))
                        }
                    }
                }
            }

            Button {
                useCustom = true
            } label: {
                HStack {
                    Text("Custom")
                        .foregroundStyle(.primary)
                    Spacer()
                    if useCustom {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .font(AppTheme.Typography.caption.weight(.semibold))
                    }
                }
            }

            if useCustom {
                HStack {
                    TextField("Seconds", text: $customSeconds)
                        .keyboardType(.numberPad)
                        .font(AppTheme.Typography.body)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                        .font(AppTheme.Typography.callout)
                }
            }
        }
    }

    private func seedFromMode() {
        guard case .edit(let task) = mode else { return }
        title = task.title
        prompt = task.intentDetail ?? ""
        let schedule = task.schedule
        if Preset.options.contains(where: { $0.schedule == schedule }) {
            selectedSchedule = schedule
            useCustom = false
        } else if let seconds = secondsFromCustomSchedule(schedule) {
            customSeconds = "\(seconds)"
            useCustom = true
        } else {
            selectedSchedule = "daily"
            useCustom = false
        }
    }

    private func secondsFromCustomSchedule(_ schedule: String) -> Int? {
        guard schedule.hasPrefix("every "), schedule.hasSuffix("s") else { return nil }
        let start = schedule.index(schedule.startIndex, offsetBy: 6)
        let end = schedule.index(before: schedule.endIndex)
        return Int(schedule[start..<end])
    }

    private func commitSave() {
        guard let schedule = resolvedSchedule else { return }
        onSave(title.trimmed, prompt.trimmed, schedule)
        Haptics.success()
        dismiss()
    }
}
