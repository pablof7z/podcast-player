import SwiftUI

// MARK: - TranscriptsSettingsView
//
// Settings → Transcripts. Three controls:
//   1. ElevenLabs Scribe model picker (the STT model identifier).
//   2. Toggle: auto-ingest publisher transcripts as they appear in feeds.
//   3. Toggle: when no publisher transcript exists, fall back to Scribe.
//
// All three persist into `Settings`. The pipeline (`TranscriptIngestService`)
// reads the toggles before kicking off any background work.

struct TranscriptsSettingsView: View {
    @Environment(AppStateStore.self) private var store

    /// Known ElevenLabs Scribe model IDs. The textfield below allows arbitrary
    /// input so future model variants don't require a code change, but the
    /// picker covers the common ones.
    private static let scribeModels: [(id: String, label: String)] = [
        ("scribe_v1", "Scribe v1 (default)"),
        ("scribe_v1_experimental", "Scribe v1 — experimental"),
    ]

    var body: some View {
        Form {
            modelSection
            automationSection
        }
        .navigationTitle("Transcripts")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section {
            Picker(selection: modelBinding) {
                ForEach(Self.scribeModels, id: \.id) { entry in
                    Text(entry.label).tag(entry.id)
                }
                if !Self.scribeModels.contains(where: { $0.id == store.state.settings.elevenLabsSTTModel }) {
                    Text(store.state.settings.elevenLabsSTTModel + " (custom)")
                        .tag(store.state.settings.elevenLabsSTTModel)
                }
            } label: {
                Label("Scribe Model", systemImage: "waveform.badge.mic")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Speech-to-Text")
        } footer: {
            Text("ElevenLabs Scribe model used when transcribing episodes that don't ship a publisher transcript.")
        }
    }

    private var automationSection: some View {
        Section {
            Toggle(isOn: autoIngestBinding) {
                Label("Auto-ingest publisher transcripts", systemImage: "square.and.arrow.down.fill")
            }
            Toggle(isOn: scribeFallbackBinding) {
                Label("Fall back to Scribe", systemImage: "arrow.triangle.branch")
            }
        } header: {
            Text("Automation")
        } footer: {
            Text("Auto-ingest pre-fetches transcripts in the background as new episodes appear. Scribe fallback transcribes audio when the publisher hasn't supplied a transcript — requires an ElevenLabs key.")
        }
    }

    // MARK: - Bindings

    private var modelBinding: Binding<String> {
        Binding(
            get: { store.state.settings.elevenLabsSTTModel },
            set: { v in
                var s = store.state.settings
                s.elevenLabsSTTModel = v
                store.updateSettings(s)
                Haptics.selection()
            }
        )
    }

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
