import SwiftUI

// MARK: - WikiSettingsView
//
// Settings → Wiki. Controls wiki automation. The compilation model is selected
// under Settings → Intelligence → Models → Wiki.

struct WikiSettingsView: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        Form {
            automationSection
        }
        .navigationTitle("Wiki")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var automationSection: some View {
        Section {
            Toggle(isOn: autoGenerateBinding) {
                Label("Generate when transcript ingests", systemImage: "sparkles.rectangle.stack.fill")
            }
        } footer: {
            Text("When on, finishing a transcript automatically refreshes any existing wiki pages whose topics overlap with the new episode. Choose the compilation model in Models → Wiki.")
        }
    }

    // MARK: - Bindings

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
}
