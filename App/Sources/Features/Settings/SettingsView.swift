import SwiftUI

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var showClearConfirm = false

    var body: some View {
        List {
            configurationSection
            destructiveSection
            versionFooterSection
        }
        .settingsListStyle()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Clear All Data?", isPresented: $showClearConfirm) {
            Button("Clear Everything", role: .destructive) {
                store.clearAllData()
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all subscriptions, episodes, notes, friends, and memories. API credentials and Nostr identity are preserved.")
        }
    }

    // MARK: - Sections

    private var configurationSection: some View {
        Section("Configuration") {
            NavigationLink {
                AISettingsView()
            } label: {
                SettingsRow(
                    icon: "sparkles",
                    tint: .blue,
                    title: "AI",
                    value: currentModelShortName
                )
            }

            NavigationLink {
                AgentSettingsView()
            } label: {
                SettingsRow(
                    icon: "brain.head.profile",
                    tint: .orange,
                    title: "Agent",
                    badge: store.pendingNostrApprovals.count
                )
            }

            NavigationLink {
                NotificationSettingsView()
            } label: {
                SettingsRow(
                    icon: "bell.badge",
                    tint: .red,
                    title: "Notifications"
                )
            }

            NavigationLink {
                DataExportView()
            } label: {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    tint: .teal,
                    title: "Data & Export",
                    value: dataRecordCount > 0 ? "\(dataRecordCount) records" : nil
                )
            }
        }
    }

    private var destructiveSection: some View {
        Section {
            Button("Clear All Data", role: .destructive) {
                showClearConfirm = true
            }
        } footer: {
            Text("Permanently deletes all subscriptions, episodes, notes, friends, and memories. API credentials and Nostr identity are preserved.")
        }
    }

    private var versionFooterSection: some View {
        Section {
        } footer: {
            Text(appVersionFooter)
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Derived values

    /// Total number of user-generated records that would be included in a data export.
    private var dataRecordCount: Int {
        store.state.subscriptions.count
            + store.state.episodes.count
            + store.activeNotes.count
            + store.activeMemories.count
            + store.state.friends.count
    }

    private var currentModelShortName: String {
        Settings.modelDisplayName(
            modelID: store.state.settings.llmModel,
            modelName: store.state.settings.llmModelName
        )
    }

    private var appVersionFooter: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Podcastr  \(version)  (build \(build))"
    }
}
