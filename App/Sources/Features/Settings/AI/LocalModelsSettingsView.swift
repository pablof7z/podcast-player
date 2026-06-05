import SwiftUI

struct LocalModelsSettingsView: View {
    @Environment(AppStateStore.self) private var store

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
        .navigationTitle("Local")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var modelsSection: some View {
        Section {
            ForEach(LocalModelCatalog.all, id: \.id) { spec in
                // Download state comes from the unified kernel download snapshot
                // (in-flight) + disk (downloaded). No bespoke manager.
                LocalModelRowView(
                    spec: spec,
                    state: store.localModelState(for: spec),
                    onDownload: {
                        store.kernelDownloadLocalModel(
                            modelID: spec.id, url: spec.downloadURL.absoluteString)
                    },
                    onCancel: { store.kernelCancelLocalModelDownload(modelID: spec.id) },
                    onDelete: {
                        try? FileManager.default.removeItem(
                            at: DownloadCapability.localModelFileURL(for: spec.id))
                    }
                )
            }
        } header: {
            Text("Available Models")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Models run fully on-device with no internet connection required. Large downloads (~2.6 GB) — Wi-Fi recommended. Once downloaded, a model becomes selectable under Models for each role, alongside your cloud providers.")
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
