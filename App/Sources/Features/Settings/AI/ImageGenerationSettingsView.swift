import SwiftUI

// MARK: - ImageGenerationSettingsView
//
// Settings for the image-generation pipeline used by the agent's
// `generate_podcast_artwork` tool: image model (via OpenRouter) and the
// Blossom upload server URL.

struct ImageGenerationSettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var settings = Settings()
    @State private var selectorPresented = false
    @State private var catalog = OpenRouterModelSelectorViewModel()

    private static let knownModels: [(id: String, label: String)] = [
        ("openai/dall-e-3",            "DALL-E 3"),
        ("openai/dall-e-2",            "DALL-E 2"),
        ("black-forest-labs/FLUX-1.1-pro", "FLUX 1.1 Pro"),
        ("black-forest-labs/FLUX-schnell", "FLUX Schnell"),
    ]

    var body: some View {
        Form {
            modelSection
            blossomSection
        }
        .navigationTitle("Image Generation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { settings = store.state.settings }
        .onChange(of: settings) { _, new in store.updateSettings(new) }
        .task { await catalog.loadIfNeeded() }
        .sheet(isPresented: $selectorPresented) {
            NavigationStack {
                OpenRouterModelSelectorView(
                    selectedModelID: modelIDBinding,
                    selectedModelName: modelNameBinding,
                    role: "Image Generation"
                )
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section {
            Button {
                selectorPresented = true
            } label: {
                SettingsRow(
                    icon: "photo.badge.sparkle",
                    tint: .pink,
                    title: "Model",
                    subtitle: modelDisplayName
                )
            }
            .buttonStyle(.pressable)
        } header: {
            Text("OpenRouter Model")
        } footer: {
            Text("The image model used by generate_podcast_artwork. Requires an OpenRouter key configured in Providers.")
        }
    }

    private var blossomSection: some View {
        Section {
            HStack {
                Label("Server URL", systemImage: "server.rack")
                Spacer()
                TextField("https://blossom.primal.net", text: $settings.blossomServerURL)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.secondary)
                    .font(AppTheme.Typography.caption)
            }
        } header: {
            Text("Blossom Upload")
        } footer: {
            Text("Generated artwork, episode audio, chapters, and transcripts are uploaded here before being referenced in Nostr events.")
        }
    }

    // MARK: - Helpers

    private var modelDisplayName: String {
        Settings.modelDisplayName(
            modelID: settings.imageGenerationModel,
            modelName: settings.imageGenerationModelName
        )
    }

    private var modelIDBinding: Binding<String> {
        Binding(
            get: { settings.imageGenerationModel },
            set: { settings.imageGenerationModel = $0 }
        )
    }

    private var modelNameBinding: Binding<String> {
        Binding(
            get: { settings.imageGenerationModelName },
            set: { settings.imageGenerationModelName = $0 }
        )
    }
}
