import SwiftUI

/// Sheet for kicking off a `podcast.tts.generate` action (feature #43).
///
/// Two inputs: a topic `TextField` and a `Stepper` for length in
/// minutes (1–15, matching the Rust handler's `MAX_LENGTH_MINUTES`
/// clamp). Tapping "Generate" dispatches and dismisses immediately —
/// the kernel responds synchronously with the new episode id and the
/// list view re-renders on the next snapshot tick.
struct GenerateTtsSheet: View {

    @Binding var isPresented: Bool
    @Environment(KernelModel.self) private var model

    @State private var topic: String = ""
    @State private var lengthMinutes: Int = 5
    @FocusState private var topicFocused: Bool

    private var canGenerate: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. AI news this week", text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($topicFocused)
                        .accessibilityIdentifier("tts-topic-field")
                } header: {
                    Text("Topic")
                } footer: {
                    Text("The agent will narrate a short episode about this topic.")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Stepper(value: $lengthMinutes, in: 1...15) {
                        HStack {
                            Text("Length")
                            Spacer()
                            Text("\(lengthMinutes) min")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("tts-length-stepper")
                } header: {
                    Text("Length")
                }
            }
            .navigationTitle("New AI Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Generate", action: generate)
                        .disabled(!canGenerate)
                        .accessibilityIdentifier("tts-generate-confirm")
                }
            }
            .onAppear { topicFocused = true }
        }
    }

    private func generate() {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.dispatch(
            namespace: "podcast.tts",
            body: [
                "op": "generate",
                "topic": trimmed,
                "length_minutes": lengthMinutes,
            ]
        )
        Haptics.success()
        isPresented = false
    }
}
