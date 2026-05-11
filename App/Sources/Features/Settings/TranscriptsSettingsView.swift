import SwiftUI

// MARK: - TranscriptsSettingsView
//
// Settings → Transcripts. Controls transcript automation:
//   1. Toggle: auto-ingest publisher transcripts as they appear in feeds.
//   2. Toggle: when no publisher transcript exists, fall back to Scribe.
//
// Speech model selection lives under Settings → Intelligence → Models → Speech.

struct TranscriptsSettingsView: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        Form {
            automationSection
        }
        .navigationTitle("Transcripts")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var automationSection: some View {
        Section {
            Toggle(isOn: autoIngestBinding) {
                Label("Auto-ingest publisher transcripts", systemImage: "square.and.arrow.down.fill")
            }
            Toggle(isOn: scribeFallbackBinding) {
                Label("Fall back to Scribe", systemImage: "arrow.triangle.branch")
            }
            if store.state.settings.autoFallbackToScribe && !hasElevenLabsKey {
                // The toggle is on but the dependency isn't set up — surface
                // the gap inline rather than letting the fallback silently
                // no-op when an episode actually needs transcription.
                Label("Requires an ElevenLabs API key — connect in Providers.", systemImage: "key.slash")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 2)
            }
        } header: {
            Text("Automation")
        } footer: {
            Text("Auto-ingest pre-fetches transcripts in the background as new episodes appear. Scribe fallback transcribes audio when the publisher hasn't supplied a transcript. Choose the Scribe model in Models → Speech.")
        }
    }

    private var hasElevenLabsKey: Bool {
        store.state.settings.elevenLabsCredentialSource != .none
    }

    // MARK: - Bindings

    private var autoIngestBinding: Binding<Bool> {
        Binding(
            get: { store.state.settings.autoIngestPublisherTranscripts },
            set: { v in
                var s = store.state.settings
                s.autoIngestPublisherTranscripts = v
                store.updateSettings(s)
                Haptics.selection()
            }
        )
    }

    private var scribeFallbackBinding: Binding<Bool> {
        Binding(
            get: { store.state.settings.autoFallbackToScribe },
            set: { v in
                var s = store.state.settings
                s.autoFallbackToScribe = v
                store.updateSettings(s)
                Haptics.selection()
            }
        )
    }
}
