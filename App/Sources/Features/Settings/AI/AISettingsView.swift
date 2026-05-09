import SwiftUI

struct AISettingsView: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            List {
                llmSection
                audioSection
                ragSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var llmSection: some View {
        Section("LLM") {
            NavigationLink {
                LLMSettingsView()
            } label: {
                SettingsRow(
                    icon: "cpu",
                    tint: .purple,
                    title: "Language Models",
                    subtitle: agentModelShortName,
                    value: providerStatus
                )
            }

            NavigationLink {
                WikiSettingsView()
            } label: {
                SettingsRow(
                    icon: "book.closed.fill",
                    tint: .indigo,
                    title: "Wiki",
                    subtitle: wikiModelShortName
                )
            }
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            NavigationLink {
                ElevenLabsSettingsView()
            } label: {
                SettingsRow(
                    icon: "waveform",
                    tint: .teal,
                    title: "ElevenLabs",
                    value: elevenLabsStatus
                )
            }
        }
    }

    /// "Knowledge" surfaces the retrieval-augmented generation configuration.
    /// Embedding model changes should be treated as an index-level choice:
    /// the live client enforces the current 1024-d vector contract.
    private var ragSection: some View {
        Section {
            NavigationLink {
                LLMSettingsView()
            } label: {
                SettingsRow(
                    icon: "rectangle.stack.fill.badge.person.crop",
                    tint: .blue,
                    title: "Embeddings",
                    value: Settings.embeddingsModelDisplay(
                        modelID: settings.embeddingsModel,
                        modelName: settings.embeddingsModelName
                    )
                )
            }
            Toggle(isOn: rerankerBinding) {
                Label("Reranker", systemImage: "list.number")
            }
        } header: {
            Text("Knowledge")
        } footer: {
            Text("Embeddings power on-device search and the agent's evidence retrieval. The reranker reorders top results with a cross-encoder for higher quality at extra token cost.")
        }
    }

    // MARK: - Bindings

    private var rerankerBinding: Binding<Bool> {
        Binding(
            get: { store.state.settings.rerankerEnabled },
            set: { v in
                var s = store.state.settings
                s.rerankerEnabled = v
                store.updateSettings(s)
                Haptics.selection()
            }
        )
    }

    // MARK: - Derived

    private var settings: Settings { store.state.settings }

    private var agentModelShortName: String? {
        let name = Settings.modelDisplayName(modelID: settings.llmModel, modelName: settings.llmModelName)
        return name == "Not set" ? nil : name
    }

    private var wikiModelShortName: String? {
        let name = Settings.modelDisplayName(modelID: settings.wikiModel, modelName: settings.wikiModelName)
        return name == "Not set" ? nil : name
    }

    private var providerStatus: String {
        let openRouterReady = settings.openRouterCredentialSource != .none
        let ollamaReady = settings.ollamaCredentialSource != .none
        switch (openRouterReady, ollamaReady) {
        case (true, true):   return "2 providers"
        case (true, false):  return "OpenRouter"
        case (false, true):  return "Ollama"
        case (false, false): return "Not set up"
        }
    }

    private var elevenLabsStatus: String {
        switch settings.elevenLabsCredentialSource {
        case .byok:   return "BYOK"
        case .manual: return "Manual"
        case .none:   return "Not set up"
        }
    }
}
