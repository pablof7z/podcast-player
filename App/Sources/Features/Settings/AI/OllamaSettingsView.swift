import SwiftUI

struct OllamaSettingsView: View {
    @Environment(AppStateStore.self) private var store

    @State private var settings = Settings()
    @State private var manualAPIKey = ""
    @State private var hasStoredKey = false
    @State private var isValidating = false
    @State private var credentialMessage: String?
    @State private var credentialError: String?
    @State private var modelCount: Int?

    private let catalog = OllamaModelCatalogService()

    var body: some View {
        Form {
            connectionSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ollama Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = store.state.settings
            refreshCredentialState()
        }
        .onChange(of: settings) { _, new in store.updateSettings(new) }
        .animation(AppTheme.Animation.spring, value: credentialMessage)
        .animation(AppTheme.Animation.spring, value: credentialError)
        .animation(AppTheme.Animation.spring, value: modelCount)
    }

    private var connectionSection: some View {
        Section {
            Label(statusTitle, systemImage: statusIcon)
                .foregroundStyle(statusColor)

            RevealableAPIKeyField("Paste Ollama API key", text: $manualAPIKey)

            Button {
                saveManualKey()
            } label: {
                Label("Save Manual Key", systemImage: "square.and.arrow.down")
            }
            .disabled(manualAPIKey.isBlank)

            if hasStoredKey {
                Button {
                    Task { await validateStoredKey() }
                } label: {
                    HStack {
                        Label(isValidating ? "Checking models..." : "Check Available Models", systemImage: "list.bullet.rectangle")
                        if isValidating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isValidating)

                Button(role: .destructive) {
                    disconnect()
                } label: {
                    Label("Disconnect", systemImage: "trash")
                }
            }

            if let modelCount {
                Text("\(modelCount) Ollama Cloud models available for selection.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if let credentialMessage {
                Text(credentialMessage)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if let credentialError {
                Text(credentialError)
                    .inlineErrorText()
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Create an Ollama API key on ollama.com. The key is stored only in Keychain and is used for model browsing, chat, and embeddings.")
        }
    }

    private var statusTitle: String {
        guard hasStoredKey else {
            return settings.ollamaCredentialSource == .none ? "Not connected" : "Reconnect required"
        }
        return "Manual key saved"
    }

    private var statusIcon: String {
        hasStoredKey ? "checkmark.seal.fill" : "xmark.seal"
    }

    private var statusColor: Color {
        hasStoredKey ? .green : .secondary
    }

    private func saveManualKey() {
        credentialError = nil
        credentialMessage = nil
        modelCount = nil
        do {
            try OllamaCredentialStore.saveAPIKey(manualAPIKey)
            settings.markOllamaManual()
            store.updateSettings(settings)
            manualAPIKey = ""
            refreshCredentialState()
            credentialMessage = "Ollama key saved in Keychain."
            Haptics.success()
        } catch {
            credentialError = "Ollama key could not be saved."
            Haptics.error()
        }
    }

    private func disconnect() {
        credentialError = nil
        credentialMessage = nil
        modelCount = nil
        do {
            try OllamaCredentialStore.deleteAPIKey()
            settings.clearOllamaCredential()
            store.updateSettings(settings)
            manualAPIKey = ""
            refreshCredentialState()
            credentialMessage = "Ollama disconnected."
            Haptics.success()
        } catch {
            credentialError = "Ollama key could not be deleted."
            Haptics.error()
        }
    }

    private func refreshCredentialState() {
        hasStoredKey = OllamaCredentialStore.hasAPIKey()
    }

    private func validateStoredKey() async {
        credentialError = nil
        credentialMessage = nil
        modelCount = nil
        isValidating = true
        defer { isValidating = false }

        do {
            let models = try await catalog.fetchModels()
            modelCount = models.count
            Haptics.success()
        } catch {
            credentialError = error.localizedDescription
            Haptics.warning()
        }
    }
}
