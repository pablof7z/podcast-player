import SwiftUI

// MARK: - WikiSettingsView
//
// Settings → Wiki. Lets the user pick the LLM model used for wiki compilation
// and decide whether new transcripts should auto-trigger a wiki refresh.
//
// The wiki model is intentionally separate from `Settings.llmModel` (the agent
// chat model) and from `Settings.memoryCompilationModel` so users can pair a
// fast/cheap model with bulk compilation while keeping a stronger model for
// live conversation. Same pattern as memory compilation already uses.

struct WikiSettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var modelSelectorPresented = false
    @State private var catalog = OpenRouterModelSelectorViewModel()

    var body: some View {
        Form {
            modelSection
            automationSection
        }
        .navigationTitle("Wiki")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await catalog.loadIfNeeded()
            backfillModelName()
        }
        .sheet(isPresented: $modelSelectorPresented) {
            NavigationStack {
                OpenRouterModelSelectorView(
                    selectedModelID: modelIDBinding,
                    selectedModelName: modelNameBinding,
                    role: "Wiki"
                )
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section {
            Button {
                modelSelectorPresented = true
            } label: {
                SettingsRow(
                    icon: "book.closed.fill",
                    tint: .indigo,
                    title: "Compilation Model",
                    subtitle: displayName
                )
            }
            .buttonStyle(.pressable)
        } header: {
            Text("Model")
        } footer: {
            Text("Used by the wiki generator to summarise transcripts into evidence-cited pages. Defaults to openai/gpt-4o-mini.")
        }
    }

    private var automationSection: some View {
        Section {
            Toggle(isOn: autoGenerateBinding) {
                Label("Generate when transcript ingests", systemImage: "sparkles.rectangle.stack.fill")
            }
        } footer: {
            Text("When on, finishing a transcript automatically refreshes any existing wiki pages whose topics overlap with the new episode. New pages are still created on demand from the Wiki tab.")
        }
    }

    // MARK: - Bindings

    private var modelIDBinding: Binding<String> {
        Binding(
            get: { store.state.settings.wikiModel },
            set: { v in
                var s = store.state.settings
                s.wikiModel = v
                store.updateSettings(s)
            }
        )
    }

    private var modelNameBinding: Binding<String> {
        Binding(
            get: { store.state.settings.wikiModelName },
            set: { v in
                var s = store.state.settings
                s.wikiModelName = v
                store.updateSettings(s)
            }
        )
    }

    private var autoGenerateBinding: Binding<Bool> {
        Binding(
            get: { store.state.settings.wikiAutoGenerateOnTranscriptIngest },
            set: { v in
                var s = store.state.settings
                s.wikiAutoGenerateOnTranscriptIngest = v
                store.updateSettings(s)
                Haptics.selection()
            }
        )
    }

    // MARK: - Helpers

    private var displayName: String {
        Settings.modelDisplayName(
            modelID: store.state.settings.wikiModel,
            modelName: store.state.settings.wikiModelName
        )
    }

    /// Backfills the persisted human-readable model name from the catalog so
    /// existing installs without `wikiModelName` get a friendly label as soon
    /// as the catalog finishes loading.
    private func backfillModelName() {
        var s = store.state.settings
        guard s.wikiModelName.isEmpty,
              let match = catalog.models.first(where: { $0.id == s.wikiModel })
        else { return }
        s.wikiModelName = match.name
        store.updateSettings(s)
    }
}
