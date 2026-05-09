import SwiftUI

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var showClearConfirm = false

    var body: some View {
        List {
            if showMomentum { momentumSection }
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
            Text("This will permanently delete all items, notes, friends, and memories. API credentials are preserved.")
        }
    }

    // MARK: - Sections

    private var showMomentum: Bool {
        store.completionStreak > 0 || store.weeklyCompletions.contains(where: { $0 > 0 })
    }

    private var momentumSection: some View {
        Section {
            HStack(spacing: 0) {
                VStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: store.completionStreak > 0 ? "flame.fill" : "flame")
                            .foregroundStyle(store.completionStreak > 0 ? .orange : .secondary)
                            .accessibilityHidden(true)
                        Text("\(store.completionStreak)")
                            .font(AppTheme.Typography.title3)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Text(store.completionStreak == 1 ? "day streak" : "days streak")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 32)

                VStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
                    Text("\(store.weeklyCompletions.reduce(0, +))")
                        .font(AppTheme.Typography.title3)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("done this week")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, AppTheme.Spacing.xs)
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
        } header: {
            Text("Momentum")
        }
    }

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
                    title: "Notifications",
                    value: store.remindersItemCount > 0 ? "\(store.remindersItemCount) scheduled" : nil
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
            Text("Permanently deletes all items, notes, friends, and memories. API credentials and Nostr identity are preserved.")
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
        let items = store.nonDeletedItemCount
        let notes = store.activeNotes.count
        let memories = store.activeMemories.count
        return items + notes + memories
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
        return "App Template  \(version)  (build \(build))"
    }
}
