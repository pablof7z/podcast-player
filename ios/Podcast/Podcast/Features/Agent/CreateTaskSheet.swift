import SwiftUI

// MARK: - CreateTaskSheet
//
// Sheet presented from `AgentTasksView` toolbar `+`. Collects a typed
// task intent and dispatches `podcast.tasks.create_from_intent` when
// Save is tapped. The action's reducer mints the task UUID; this view
// never invents an id locally.

struct CreateTaskSheet: View {

    @Environment(KernelModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var schedule: ScheduleOption = .daily
    @State private var intentPreset: IntentPreset = .inboxTriage
    @State private var memoryKey: String = ""
    @State private var memoryValue: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityLabel("Task title")
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Task description")
                }

                Section("Schedule") {
                    Picker("Schedule", selection: $schedule) {
                        ForEach(ScheduleOption.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Intent") {
                    Picker("Intent", selection: $intentPreset) {
                        ForEach(IntentPreset.allCases, id: \.self) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    if intentPreset == .rememberMemory {
                        TextField("Memory key", text: $memoryKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Memory key")
                        TextField("Memory value", text: $memoryValue, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityLabel("Memory value")
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Save

    private var canSave: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return false }
        if intentPreset == .rememberMemory {
            let hasKey = !memoryKey.trimmingCharacters(in: .whitespaces).isEmpty
            let hasValue = !memoryValue.trimmingCharacters(in: .whitespaces).isEmpty
            return hasKey && hasValue
        }
        return true
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        var body: [String: Any] = [
            "op": "create_from_intent",
            "title": trimmedTitle,
            "intent": intentBody,
            "schedule": schedule.rawValue,
        ]
        if !trimmedDescription.isEmpty {
            body["description"] = trimmedDescription
        }
        model.dispatch(namespace: "podcast.tasks", body: body)
        dismiss()
    }

    private var intentBody: [String: Any] {
        switch intentPreset {
        case .inboxTriage:
            return ["type": "inbox_triage"]
        case .clearAgent:
            return ["type": "clear_agent"]
        case .rememberMemory:
            return [
                "type": "remember_memory",
                "key": memoryKey.trimmingCharacters(in: .whitespaces),
                "value": memoryValue.trimmingCharacters(in: .whitespaces),
            ]
        }
    }
}

// MARK: - Pickers

private enum ScheduleOption: String, CaseIterable {
    case daily, weekly, once
    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .once: "Once"
        }
    }
}

private enum IntentPreset: CaseIterable {
    case inboxTriage, clearAgent, rememberMemory
    var label: String {
        switch self {
        case .inboxTriage: "Inbox Triage"
        case .clearAgent: "Clear Agent Chat"
        case .rememberMemory: "Remember Memory"
        }
    }
}
