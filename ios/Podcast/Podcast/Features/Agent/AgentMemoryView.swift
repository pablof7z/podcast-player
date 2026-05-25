import SwiftUI

// MARK: - AgentMemoryView
//
// Settings-style list of agent-memory facts (feature #33). The kernel owns
// the durable store (`PodcastStore.memory_facts` ↔ `MemoryActionModule`);
// this view is a pure read of `model.podcastSnapshot?.memoryFacts ?? []`,
// plus dispatch-only mutations. No local state mirrors the bag.
//
// Wire shape (mirrors `apps/nmp-app-podcast/src/ffi/actions/memory_module.rs`):
//   podcast.memory.remember     { key, value, source? }
//   podcast.memory.forget       { key }
//   podcast.memory.forget_all   {}

struct AgentMemoryView: View {

    @Environment(KernelModel.self) private var model

    @State private var addSheetPresented = false
    @State private var clearAllConfirm = false

    private var facts: [MemoryFact] {
        model.podcastSnapshot?.memoryFacts ?? []
    }

    var body: some View {
        Group {
            if facts.isEmpty {
                emptyState
            } else {
                factList
            }
        }
        .navigationTitle("Agent Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $addSheetPresented) {
            AddMemorySheet { key, value in
                model.dispatch(
                    namespace: "podcast.memory",
                    body: ["op": "remember", "key": key, "value": value]
                )
            }
        }
        .alert("Forget all memories?", isPresented: $clearAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Forget All", role: .destructive) {
                model.dispatch(namespace: "podcast.memory", body: ["op": "forget_all"])
                Haptics.medium()
            }
        } message: {
            Text("The assistant will lose every fact it knows about you on this device.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { addSheetPresented = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add memory")
        }
        if !facts.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) {
                    clearAllConfirm = true
                } label: {
                    Text("Clear All")
                }
                .accessibilityLabel("Clear all memories")
            }
        }
    }

    // MARK: - Fact list

    private var factList: some View {
        List {
            Section {
                ForEach(facts) { fact in
                    AgentMemoryRow(fact: fact)
                }
                .onDelete(perform: deleteFacts)
            } header: {
                Text("Stored facts")
            } footer: {
                Text("Swipe a row to forget that fact, or tap Clear All to wipe the bag.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteFacts(at offsets: IndexSet) {
        for index in offsets {
            let key = facts[index].key
            model.dispatch(namespace: "podcast.memory", body: ["op": "forget", "key": key])
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Memories Yet", systemImage: "brain")
        } description: {
            Text("Tap + to record a fact the assistant should remember.")
        } actions: {
            Button { addSheetPresented = true } label: {
                Text("Add memory")
                    .font(AppTheme.Typography.headline)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Row

private struct AgentMemoryRow: View {
    let fact: MemoryFact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(fact.key)
                    .font(AppTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                sourceBadge
            }
            Text(fact.value)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fact.key): \(fact.value), recorded by \(sourceLabel)")
    }

    private var sourceLabel: String {
        fact.source == "agent" ? "Agent" : "You"
    }

    private var sourceBadge: some View {
        Text(sourceLabel)
            .font(AppTheme.Typography.caption2.weight(.semibold))
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeBackground, in: Capsule())
    }

    private var badgeForeground: Color {
        fact.source == "agent" ? .accentColor : .secondary
    }

    private var badgeBackground: Color {
        fact.source == "agent"
            ? Color.accentColor.opacity(0.15)
            : Color.secondary.opacity(0.15)
    }
}

// MARK: - Add sheet

private struct AddMemorySheet: View {

    @Environment(\.dismiss) private var dismiss

    let onSave: (_ key: String, _ value: String) -> Void

    @State private var key: String = ""
    @State private var value: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case key, value }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Key (e.g. preferred_genre)", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .key)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .value }
                    TextField("Value (e.g. technology)", text: $value, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .value)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text("The agent will read these facts when it talks to you. Keep keys short; values can be a sentence.")
                }
            }
            .navigationTitle("Add Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear { focusedField = .key }
        }
    }

    private var canSave: Bool {
        !trimmedKey.isEmpty && !trimmedValue.isEmpty
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedValue: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard canSave else { return }
        onSave(trimmedKey, trimmedValue)
        Haptics.success()
        dismiss()
    }
}
