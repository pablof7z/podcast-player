import SwiftUI

struct AssemblyAISettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var settings: Settings = Settings()
    @State private var manualAPIKey = ""
    @State private var isConnectingBYOK = false
    @State private var credentialMessage: String?
    @State private var credentialError: String?
    @State private var byokConnect = BYOKConnectService()

    var body: some View {
        Form {
            connectionSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AssemblyAI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = store.state.settings
            refreshCredentialState()
        }
        .onChange(of: settings) { _, new in store.updateSettings(new) }
        .animation(AppTheme.Animation.spring, value: credentialMessage)
        .animation(AppTheme.Animation.spring, value: credentialError)
        .animation(AppTheme.Animation.spring, value: isConnectingBYOK)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { saveManualKey() }
                    .disabled(manualAPIKey.isBlank)
            }
        }
    }

    private var connectionSection: some View {
        Section {
            Label(statusTitle, systemImage: statusIcon)
                .foregroundStyle(statusColor)

            if settings.assemblyAICredentialSource == .byok,
               let label = settings.assemblyAIBYOKKeyLabel,
               !label.isBlank {
                LabeledContent("BYOK key", value: label)
            }

            Button {
                Task { await connectWithBYOK() }
            } label: {
                HStack {
                    Label(isConnectingBYOK ? "Connecting..." : byokButtonTitle, systemImage: "key.viewfinder")
                    if isConnectingBYOK {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isConnectingBYOK)

            RevealableAPIKeyField("Paste AssemblyAI API key", text: $manualAPIKey)
                .onSubmit { saveManualKey() }

            if hasStoredKey {
                Button(role: .destructive) {
                    disconnect()
                } label: {
                    Label("Disconnect", systemImage: "trash")
                }
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
            Text("AssemblyAI powers cloud speech-to-text. Choose it for transcription in Models -> Speech.")
        }
    }

    private var hasStoredKey: Bool {
        (store.kernel?.settings ?? SettingsSnapshot()).assemblyAIKeyPresent
    }

    private var statusTitle: String {
        guard hasStoredKey else {
            return settings.assemblyAICredentialSource == .none ? "Not connected" : "Reconnect required"
        }
        switch settings.assemblyAICredentialSource {
        case .byok:   return "Connected with BYOK"
        case .manual: return "Manual key saved"
        case .none:   return "Key stored"
        }
    }

    private var statusIcon: String {
        guard hasStoredKey else {
            return settings.assemblyAICredentialSource == .none ? "xmark.seal" : "exclamationmark.triangle"
        }
        return "checkmark.seal.fill"
    }

    private var statusColor: Color {
        hasStoredKey ? .green : .secondary
    }

    private var byokButtonTitle: String {
        settings.assemblyAICredentialSource == .byok ? "Reconnect BYOK" : "Connect with BYOK"
    }

    private func connectWithBYOK() async {
        credentialError = nil
        credentialMessage = nil
        isConnectingBYOK = true
        defer { isConnectingBYOK = false }

        do {
            let token = try await byokConnect.connectAssemblyAI()
            try AssemblyAICredentialStore.saveAPIKey(token.apiKey)
            settings.markAssemblyAIBYOK(keyID: token.keyID, keyLabel: token.keyLabel)
            store.updateSettings(settings)
            manualAPIKey = ""
            refreshCredentialState()
            credentialMessage = "AssemblyAI connected with BYOK."
            Haptics.success()
        } catch BYOKConnectError.cancelled {
            Haptics.warning()
        } catch {
            credentialError = error.localizedDescription
            Haptics.error()
        }
    }

    private func saveManualKey() {
        credentialError = nil
        credentialMessage = nil
        do {
            try AssemblyAICredentialStore.saveAPIKey(manualAPIKey)
            settings.markAssemblyAIManual()
            store.updateSettings(settings)
            manualAPIKey = ""
            refreshCredentialState()
            credentialMessage = "AssemblyAI key saved in Keychain."
            Haptics.success()
        } catch {
            credentialError = "AssemblyAI key could not be saved."
            Haptics.error()
        }
    }

    private func disconnect() {
        credentialError = nil
        credentialMessage = nil
        do {
            try AssemblyAICredentialStore.deleteAPIKey()
            settings.clearAssemblyAICredential()
            store.updateSettings(settings)
            manualAPIKey = ""
            refreshCredentialState()
            credentialMessage = "AssemblyAI disconnected."
            Haptics.success()
        } catch {
            credentialError = "AssemblyAI key could not be deleted."
            Haptics.error()
        }
    }

    private func refreshCredentialState() {
        // Re-report STT key presence so the kernel's STT fallback policy
        // recomputes `settings.effectiveSttProvider` after a save/delete.
        store.syncSTTKeysPresent()
        store.kernelSetProviderApiKeys()
    }
}
