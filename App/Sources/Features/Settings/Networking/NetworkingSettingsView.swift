import SwiftUI

struct NetworkingSettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var snapshot = RelayDiagnosticsSnapshot()

    var body: some View {
        List {
            summarySection
            relaysSection
            rolesSection
        }
        .settingsListStyle()
        .navigationTitle("Networking")
        .navigationBarTitleDisplayMode(.inline)
        .task { await observeChanges() }
        .refreshable { await refresh() }
    }

    private var summarySection: some View {
        Section("Summary") {
            summaryRow("Relays", value: "\(snapshot.relays.count)")
            summaryRow("Connected", value: "\(snapshot.connectedCount)")
            summaryRow("Subscriptions", value: "\(snapshot.activeSubscriptionCount)")
            summaryRow("Messages received", value: "\(snapshot.messagesReceived)")
            summaryRow("Messages sent", value: "\(snapshot.messagesSent)")
        }
    }

    private var relaysSection: some View {
        Section {
            if snapshot.relays.isEmpty {
                ContentUnavailableView(
                    "No relays",
                    systemImage: "network.slash",
                    description: Text("Nostr networking has not been configured yet.")
                )
            } else {
                ForEach(snapshot.relays) { relay in
                    NavigationLink {
                        RelayDetailView(initialRelay: relay)
                    } label: {
                        RelayRowView(relay: relay)
                    }
                }
            }
        } header: {
            Text("Relays")
        } footer: {
            Text("Live rows come from the shared NDK relay pool. Configured rows cover direct relay clients such as feedback, profile publishing, pairing, and podcast publishing.")
        }
    }

    private var rolesSection: some View {
        Section("Roles") {
            ForEach(RelayRoleViewModel.allCases) { role in
                HStack(spacing: 10) {
                    Image(systemName: role.icon)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.rawValue)
                        Text(role.description)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func observeChanges() async {
        snapshot = await RelayDiagnosticsProvider.load(store: store)
        guard let ndk = NostrStack.shared.ndk else { return }
        for await _ in await ndk.relayChanges {
            snapshot = await RelayDiagnosticsProvider.load(store: store)
        }
    }

    private func refresh() async {
        snapshot = await RelayDiagnosticsProvider.load(store: store)
    }
}

#Preview {
    NavigationStack {
        NetworkingSettingsView()
            .environment(AppStateStore())
    }
}
