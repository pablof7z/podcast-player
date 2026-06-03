import SwiftUI

struct LocalModelsSettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var downloadManager: LocalModelDownloadManager?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            List {
                modelsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if downloadManager == nil {
                downloadManager = LocalModelDownloadManager()
            }
            // Recompute active badge from the kernel-projected localModelID now
            // that the store is available (init() ran without it).
            downloadManager?.recomputeStatesFromDisk(activeModelID: store.state.settings.localModelID)
        }
        .onChange(of: store.state.settings.localModelID) { _, newID in
            downloadManager?.recomputeStatesFromDisk(activeModelID: newID)
        }
    }

    // MARK: - Sections

    private var modelsSection: some View {
        Section {
            ForEach(LocalModelCatalog.all, id: \.id) { spec in
                if let manager = downloadManager {
                    let state = manager.state(for: spec.id)
                    LocalModelRowView(
                        spec: spec,
                        state: state,
                        onDownload: { manager.download(spec: spec) },
                        onCancel: { manager.cancel(spec.id) },
                        onActivate: { store.kernelSetLocalModel(modelID: spec.id) },
                        onDelete: { manager.delete(spec.id); if store.state.settings.localModelID == spec.id { store.kernelSetLocalModel(modelID: nil) } }
                    )
                }
            }
        } header: {
            Text("Available Models")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Models run fully on-device with no internet connection required. Large downloads (~2.6 GB) — Wi-Fi recommended. Selecting a local model makes all AI features use it until you switch back to a cloud provider.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        LocalModelsSettingsView()
            .environment(AppStateStore())
    }
}
