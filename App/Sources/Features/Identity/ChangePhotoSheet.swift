import SwiftUI

// MARK: - ChangePhotoSheet
//
// Action-sheet-style chooser per identity-05-synthesis §4.4. Two MVP entries:
// "Choose a style" (curated 6) and "Paste image URL". `Take photo` and
// `Choose from library` are listed disabled with the honest footer copy from
// the brief — they require a media host (Blossom or equivalent) which lands
// in a separate brief.

struct ChangePhotoSheet: View {

    @Binding var pictureURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var pasteURL: String = ""
    @State private var pasteVisible = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AvatarStylePickerView(pictureURL: $pictureURL)
                    } label: {
                        Label("Choose a style", systemImage: "circle.grid.3x3.fill")
                    }
                    Button {
                        pasteVisible.toggle()
                    } label: {
                        Label("Paste image URL", systemImage: "link")
                    }
                    if pasteVisible {
                        TextField("https://…", text: $pasteURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("Use this URL") {
                            pictureURL = pasteURL.trimmed
                            Haptics.success()
                            dismiss()
                        }
                        .disabled(!isValidURL(pasteURL))
                    }
                }
                Section {
                    Label("Take photo", systemImage: "camera")
                        .foregroundStyle(.tertiary)
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .foregroundStyle(.tertiary)
                } footer: {
                    Text("Photo upload arrives with a future update. For now, your photo is a generated style.")
                }
            }
            .navigationTitle("Change photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func isValidURL(_ s: String) -> Bool {
        guard let url = URL(string: s.trimmed),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
