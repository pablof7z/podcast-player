import SwiftUI

struct LocalModelRowView: View {
    let spec: LocalModelSpec
    let state: LocalModelState
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onActivate: () -> Void
    let onDelete: () -> Void

    @Environment(AppStateStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.displayName)
                        .font(.headline)
                    Text(formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                stateView
            }

            if case .downloading(let progress) = state {
                ProgressView(value: progress)
                    .tint(.blue)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - View Helpers

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: spec.sizeBytes, countStyle: .file)
    }

    @ViewBuilder
    private var stateView: some View {
        switch state {
        case .notDownloaded:
            Button(action: onDownload) {
                Text("Download")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)

        case .downloading:
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)

        case .downloaded:
            HStack(spacing: 8) {
                Button(action: onActivate) {
                    Text("Select")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("Delete", action: onDelete)
                        .foregroundStyle(.red)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }

        case .active:
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Active")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Spacer()
                }

                Button(action: { store.kernelSetLocalModel(modelID: nil) }) {
                    Text("Use Cloud Instead")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button("Delete", action: onDelete)
                        .foregroundStyle(.red)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis.circle")
                        Text("More")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    VStack {
        LocalModelRowView(spec: LocalModelCatalog.all[0], state: .notDownloaded,
                          onDownload: {}, onCancel: {}, onActivate: {}, onDelete: {})
        LocalModelRowView(spec: LocalModelCatalog.all[0], state: .downloading(progress: 0.45),
                          onDownload: {}, onCancel: {}, onActivate: {}, onDelete: {})
        LocalModelRowView(spec: LocalModelCatalog.all[0], state: .downloaded,
                          onDownload: {}, onCancel: {}, onActivate: {}, onDelete: {})
        LocalModelRowView(spec: LocalModelCatalog.all[0], state: .active,
                          onDownload: {}, onCancel: {}, onActivate: {}, onDelete: {})
    }
    .environment(AppStateStore())
}
