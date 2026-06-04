import SwiftUI

struct AgentConnectionSettingsView: View {
    @Binding var relayURL: String
    let hasPrivateKey: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                relaySection
                if hasPrivateKey {
                    privateKeySection
                }
            }
            .navigationTitle("Agent Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var relaySection: some View {
        Section {
            TextField("wss://relay.damus.io", text: $relayURL)
                .font(AppTheme.Typography.monoCallout)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        } header: {
            Label("Agent Relay", systemImage: "antenna.radiowaves.left.and.right")
        } footer: {
            Text("Your agent connects to this relay to send and receive Nostr messages — inbox delivery, profile publishing, and NIP-46 pairing.")
        }
    }

    private var privateKeySection: some View {
        Section {
            Label("Held securely by the app kernel", systemImage: "lock.shield")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
        } header: {
            Label("Private Key", systemImage: "key.fill")
        } footer: {
            // Degraded honestly: the kernel (NMP) owns the private key in a
            // zeroizing store and never returns the raw bytes to the app, so
            // the previous "reveal nsec" export is no longer possible.
            Text("Your private key is stored by the app's secure kernel and never leaves it. It cannot be exported from this screen.")
        }
    }
}
