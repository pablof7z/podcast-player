import SwiftUI

// MARK: - AddRelaySheet
//
// Compact modal form for entering a new `wss://` relay URL. Split out of
// `RelayListView.swift` to keep that file under the 300-line soft limit.
// The sheet is intentionally narrow in scope: validation lives in the
// presenting view (`RelayListView.handleAdd`) so the kernel-side rejection
// semantics stay in one place.

struct AddRelaySheet: View {

    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = "wss://"
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("wss://relay.example.com", text: $input)
                        .font(AppTheme.Typography.monoCallout)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused($fieldFocused)
                        .onSubmit(submit)
                } header: {
                    Label("Relay URL", systemImage: "antenna.radiowaves.left.and.right")
                } footer: {
                    Text("WebSocket relay URL starting with wss://. The relay you add here will be advertised in your NIP-65 relay list so other clients can find your posts.")
                }
            }
            .navigationTitle("Add Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: submit)
                        .disabled(!canSubmit)
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private var canSubmit: Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > "wss://".count
            && (trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://"))
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit(input)
    }
}
