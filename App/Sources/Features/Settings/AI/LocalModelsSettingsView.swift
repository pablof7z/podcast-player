import SwiftUI

struct LocalModelsSettingsView: View {
    @Environment(AppStateStore.self) private var store
    // The shared singleton — never construct a per-view manager: a second
    // background session for the same identifier is undefined behaviour and the
    // old one leaks, leaving the UI bound to a manager that no longer receives
    // download callbacks.
    private let downloadManager = LocalModelDownloadManager.shared

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
            // Recompute active badge from the kernel-projected localModelID now
            // that the store is available (init() ran without it). Existing
            // in-flight downloads on the shared session keep their .downloading
            // state — recompute only flips disk-backed rows.
            downloadManager.recomputeStatesFromDisk(activeModelID: store.state.settings.localModelID)
        }
        .onChange(of: store.state.settings.localModelID) { _, newID in
            downloadManager.recomputeStatesFromDisk(activeModelID: newID)
        }
    }

    // MARK: - Sections

    private var modelsSection: some View {
        Section {
            ForEach(LocalModelCatalog.all, id: \.id) { spec in
                let manager = downloadManager
                LocalModelRowView(
                    spec: spec,
                    state: manager.state(for: spec.id),
                    onDownload: { manager.download(spec: spec) },
                    onCancel: { manager.cancel(spec.id) },
                    onActivate: { store.kernelSetLocalModel(modelID: spec.id) },
                    onDelete: { manager.delete(spec.id); if store.state.settings.localModelID == spec.id { store.kernelSetLocalModel(modelID: nil) } }
                )
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
