import SwiftUI

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var showClearConfirm = false
    @State private var storageSummary: String?
    @State private var categoriesSheetPresented = false

    var body: some View {
        List {
            identitySection
            librarySection
            playbackSection
            knowledgeSection
            agentSection
            systemSection
            destructiveSection
            versionFooterSection
        }
        .settingsListStyle()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $categoriesSheetPresented) {
            CategoriesRecomputeSheet()
        }
        .task {
            // Cheap directory walk; runs once when Settings opens so the
            // Storage row can show the total without a navigation push.
            let snap = await StorageSettingsView.compute(store: store)
            await MainActor.run {
                storageSummary = snap.totalBytes > 0 ? Self.formatSize(snap.totalBytes) : nil
            }
        }
        .alert("Clear All Data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Data", role: .destructive) {
                store.clearAllData()
                Haptics.success()
            }
        } message: {
            Text("This will permanently delete every subscription, episode, note, friend, memory, and agent activity entry. API credentials and your Nostr identity are preserved.")
        }
    }

    // MARK: - Sections

    /// "Identity" sits at the top of Settings, above Library. The single row
    /// pushes `IdentityRootView`. Per identity-05-synthesis §3 + §4.1 — Identity
    /// is a top-level surface, not a Feedback concern.
    private var identitySection: some View {
        Section {
            IdentitySettingsRow()
        }
    }

    /// "Library" groups everything tied to the user's catalogue of shows.
    private var librarySection: some View {
        Section("Library") {
            NavigationLink {
                SubscriptionsListView()
            } label: {
                SettingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    tint: .pink,
                    title: "Subscriptions",
                    value: subscriptionCountLabel
                )
            }
            NavigationLink {
                CategoriesListView()
            } label: {
                SettingsRow(
                    icon: "square.grid.2x2.fill",
                    tint: .mint,
                    title: "Categories",
                    value: categoryCountLabel
                )
            }
            NavigationLink {
                DownloadsManagerView()
            } label: {
                SettingsRow(
                    icon: "arrow.down.circle.fill",
                    tint: .blue,
                    title: "Downloads",
                    value: downloadsSummaryLabel
                )
            }
        }
    }

    /// "Playback" wires the basic transport / player preferences.
    private var playbackSection: some View {
        Section("Playback") {
            NavigationLink {
                PlaybackSettingsView()
            } label: {
                SettingsRow(
                    icon: "play.rectangle.fill",
                    tint: .blue,
                    title: "Player",
                    subtitle: playbackSummary
                )
            }
        }
    }

    /// "Knowledge" pulls together the AI surfaces (chat models, embeddings,
    /// wiki, transcripts) so the user has one logical group for everything
    /// generative.
    private var knowledgeSection: some View {
        Section("Knowledge") {
            NavigationLink {
                AISettingsView()
            } label: {
                SettingsRow(
                    icon: "sparkles",
                    tint: .purple,
                    title: "AI",
                    value: currentModelShortName
                )
            }

            NavigationLink {
                WikiSettingsView()
            } label: {
                SettingsRow(
                    icon: "book.closed.fill",
                    tint: .indigo,
                    title: "Wiki",
                    subtitle: wikiModelShortName
                )
            }

            NavigationLink {
                TranscriptsSettingsView()
            } label: {
                SettingsRow(
                    icon: "captions.bubble.fill",
                    tint: .orange,
                    title: "Transcripts",
                    value: transcriptStatus
                )
            }

            Button {
                categoriesSheetPresented = true
            } label: {
                SettingsRow(
                    icon: "square.grid.2x2.fill",
                    tint: .green,
                    title: "Recompute Categories",
                    value: categoriesRowValue
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    /// "Agent" hosts the identity / friends / Nostr surface.
    private var agentSection: some View {
        Section("Agent") {
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
        }
    }

    /// "System" rounds out the rows that don't fit anywhere else.
    private var systemSection: some View {
        Section("System") {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                SettingsRow(
                    icon: "bell.badge",
                    tint: .red,
                    title: "Notifications",
                    value: notificationsRowValue
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

            NavigationLink {
                StorageSettingsView()
            } label: {
                SettingsRow(
                    icon: "internaldrive.fill",
                    tint: .gray,
                    title: "Storage",
                    value: storageSummary
                )
            }
        }
    }

    /// Shared helper so the Settings row's value matches the byte format used
    /// inside `StorageSettingsView`. `.file` style with `.useAll` units lets
    /// iOS pick the right unit per device locale (KB / MB / GB).
    static func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useAll]
        return f.string(fromByteCount: bytes)
    }

    private var destructiveSection: some View {
        Section {
            Button("Clear All Data", role: .destructive) {
                showClearConfirm = true
            }
        } footer: {
            Text("Permanently deletes every subscription, episode, note, friend, memory, and agent activity entry. API credentials and your Nostr identity are preserved.")
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

    /// Total number of records that would be wiped by "Clear All Data" (and
    /// included in a data export). Matches the field set in
    /// `DataExport.Stats` plus subscriptions + episodes for completeness.
    private var dataRecordCount: Int {
        store.state.subscriptions.count
            + store.state.episodes.count
            + store.activeNotes.count
            + store.activeMemories.count
            + store.state.friends.count
            + store.activeAgentActivityCount
    }

    private var currentModelShortName: String {
        Settings.modelDisplayName(
            modelID: store.state.settings.llmModel,
            modelName: store.state.settings.llmModelName
        )
    }

    private var wikiModelShortName: String? {
        let name = Settings.modelDisplayName(
            modelID: store.state.settings.wikiModel,
            modelName: store.state.settings.wikiModelName
        )
        return name == "Not set" ? nil : name
    }

    private var subscriptionCountLabel: String? {
        let count = store.state.subscriptions.count
        guard count > 0 else { return nil }
        return "\(count)"
    }

    private var categoryCountLabel: String? {
        let count = store.state.categories.count
        guard count > 0 else { return nil }
        return "\(count)"
    }

    private var downloadsSummaryLabel: String? {
        var active = 0
        var failed = 0
        var downloaded = 0
        for episode in store.state.episodes {
            switch episode.downloadState {
            case .queued, .downloading:
                active += 1
            case .failed:
                failed += 1
            case .downloaded:
                downloaded += 1
            case .notDownloaded:
                break
            }
        }
        if active > 0 { return "\(active) active" }
        if failed > 0 { return "\(failed) failed" }
        if downloaded > 0 { return "\(downloaded) saved" }
        return nil
    }

    private var playbackSummary: String {
        let s = store.state.settings
        let rate: String
        if abs(s.defaultPlaybackRate - 1.0) < 0.001 {
            rate = "1×"
        } else {
            rate = String(format: "%.1f×", s.defaultPlaybackRate)
        }
        return "\(rate) · \(s.skipBackwardSeconds)s back · \(s.skipForwardSeconds)s forward"
    }

    private var transcriptStatus: String {
        let s = store.state.settings
        switch (s.autoIngestPublisherTranscripts, s.autoFallbackToScribe) {
        case (true, true):  return "Auto + Scribe"
        case (true, false): return "Auto only"
        case (false, true): return "Scribe fallback"
        case (false, false): return "Manual"
        }
    }

    /// Trailing label for the Categories row — surfaces the cached count so
    /// the user knows the feature has been run before opening the sheet.
    private var categoriesRowValue: String? {
        let count = store.state.categories.count
        guard count > 0 else { return nil }
        return "\(count)"
    }

    private var notificationsRowValue: String? {
        let s = store.state.settings
        var on: [String] = []
        if s.notifyOnNewEpisodes  { on.append("Episodes") }
        if s.notifyOnBriefingReady { on.append("Briefings") }
        if on.isEmpty { return "Off" }
        if on.count == 2 { return "On" }
        return on.first
    }

    private var appVersionFooter: String { Self.cachedVersionFooter }

    /// `Bundle.main`'s short version + build are invariant for the
    /// process, but `appVersionFooter` runs on every Settings render.
    /// Resolve once at type-load and reuse.
    private static let cachedVersionFooter: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Podcastr  \(version)  (build \(build))"
    }()
}
