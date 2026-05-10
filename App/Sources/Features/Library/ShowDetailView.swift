import SwiftUI

// MARK: - ShowDetailView

/// Show-level detail screen pushed from `LibraryView`'s grid.
///
/// **Composition:**
///   - `ShowDetailHeader` — artwork-tinted hero (matte).
///   - Description block — feed `<description>` body text.
///   - Filter rail (chips) — same `LibraryFilter` enum as the tab.
///   - Episode list — `EpisodeRow` × N, tapping pushes
///     `LibraryEpisodeRoute` onto the enclosing `NavigationStack`.
///
/// **Glass usage:** none on the body. The "Settings for this show" sheet
/// (presented from the toolbar `…` menu) is structurally glass.
struct ShowDetailView: View {

    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subscription: PodcastSubscription

    @State private var filter: LibraryFilter = .all
    @State private var showSettings: Bool = false
    @State private var showUnsubscribeConfirm: Bool = false
    /// Drives the VoiceOver "Open episode details" custom action — bound into
    /// `ShowDetailEpisodeList` and consumed via `.navigationDestination(item:)`
    /// so the same `EpisodeDetailView` opens regardless of how the user got there.
    @State private var voiceOverDetailRoute: LibraryEpisodeRoute?
    /// Controls whether the show description is shown collapsed (≤ 5 lines)
    /// or fully expanded. Many feeds publish multi-paragraph "About this
    /// show" blurbs; folding them by default keeps the surface scannable.
    @State private var descriptionExpanded: Bool = false

    var body: some View {
        List {
            Section {
                ShowDetailHeader(
                    subscription: liveSubscription,
                    episodeCount: episodes.count
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                description
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: AppTheme.Spacing.lg,
                        bottom: 0,
                        trailing: AppTheme.Spacing.lg
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                filterSection
                    .listRowInsets(EdgeInsets(
                        top: AppTheme.Spacing.md,
                        leading: 0,
                        bottom: AppTheme.Spacing.sm,
                        trailing: 0
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            episodeListSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(liveSubscription.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { await refresh() }
        .sheet(isPresented: $showSettings) {
            ShowDetailSettingsSheet(
                subscription: liveSubscription,
                store: store,
                onDismiss: { showSettings = false },
                onUnsubscribe: { confirmUnsubscribe() }
            )
        }
        // `.alert` rather than `.confirmationDialog` because the dialog is
        // anchored to the toolbar's `Menu`. iOS 26 renders confirmationDialog
        // anchored to a menu as a popover and elides any `role: .cancel`
        // button (the popover's tap-outside-to-dismiss is treated as the
        // implicit cancel). That leaves the user staring at a single red
        // "Unsubscribe" button with no visible escape — a real UX trap for a
        // destructive action that wipes thousands of episodes. `.alert` is
        // a centred modal and reliably renders both buttons regardless of
        // anchor context.
        .alert(
            "Unsubscribe from \(liveSubscription.title)?",
            isPresented: $showUnsubscribeConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Unsubscribe", role: .destructive) { performUnsubscribe() }
        } message: {
            Text("This removes the show and all of its episodes from your library.")
        }
        .navigationDestination(for: LibraryEpisodeRoute.self) { route in
            LibraryEpisodePlaceholder(route: route)
        }
        .navigationDestination(item: $voiceOverDetailRoute) { route in
            LibraryEpisodePlaceholder(route: route)
        }
    }

    // MARK: - Live snapshot

    /// Re-read the subscription from the store on every render so settings
    /// updates (notifications toggle, refresh metadata) are reflected.
    private var liveSubscription: PodcastSubscription {
        store.subscription(id: subscription.id) ?? subscription
    }

    private var episodes: [Episode] {
        store.episodes(forSubscription: subscription.id)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var description: some View {
        // Use the shared formatter so HTML entities (&rsquo;, &mdash;, …)
        // decode to the right glyph instead of bleeding through as
        // literals. The previous regex strip only removed tags.
        let body = EpisodeShowNotesFormatter.plainText(from: liveSubscription.description)
        if !body.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(body)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionExpanded ? nil : 5)
                    .animation(.easeInOut(duration: 0.2), value: descriptionExpanded)
                if Self.descriptionNeedsToggle(body) {
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            descriptionExpanded.toggle()
                        }
                    } label: {
                        Text(descriptionExpanded ? "Show less" : "Show more")
                            .font(AppTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Approximate "is this longer than the 5-line cap" check. Counts the
    /// blocks an `EpisodeShowNotesFormatter`-collapsed string produces.
    /// Imperfect — wide characters or narrow widths still vary — but the
    /// false-positive cost is just an inert "Show more" button on a body
    /// that already fits, which is preferable to silently truncating with
    /// no escape hatch.
    static func descriptionNeedsToggle(_ body: String) -> Bool {
        // Hand-tuned thresholds: very long single-line blurbs OR multiple
        // paragraphs both warrant the toggle.
        if body.count > 240 { return true }
        let blocks = body.split(separator: "\n\n").count
        return blocks > 1
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Episodes")
                .font(AppTheme.Typography.title)
                .padding(.horizontal, AppTheme.Spacing.lg)

            LibraryFilterRail(selection: $filter)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
        }
    }

    @ViewBuilder
    private var episodeListSection: some View {
        let visible = filteredEpisodes()
        if visible.isEmpty {
            Section {
                ContentUnavailableView(
                    episodes.isEmpty ? "No episodes yet" : "No episodes match",
                    systemImage: "tray",
                    description: Text(
                        episodes.isEmpty
                        ? "Pull down to refresh this feed."
                        : "Try a different filter."
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.top, AppTheme.Spacing.xl)
            }
        } else {
            Section {
                ShowDetailEpisodeList(
                    subscription: liveSubscription,
                    episodes: visible,
                    voiceOverDetailRoute: $voiceOverDetailRoute
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Haptics.light()
                    showSettings = true
                } label: {
                    Label("Settings for this show", systemImage: "slider.horizontal.3")
                }
                // Share-show — recipients with podcast apps will recognize
                // the RSS URL and subscribe; everyone else gets a clickable
                // link with the show name above it via SharePreview.
                ShareLink(
                    item: liveSubscription.feedURL,
                    preview: SharePreview(
                        sharePreviewTitle,
                        image: Image(systemName: "antenna.radiowaves.left.and.right")
                    )
                ) {
                    Label("Share show", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    Haptics.warning()
                    showUnsubscribeConfirm = true
                } label: {
                    Label("Unsubscribe", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Show options")
        }
    }

    /// "Show by Author" when the author is known, otherwise just the title.
    /// Used as the SharePreview header so destination apps see the show
    /// name + attribution rather than the raw RSS URL.
    private var sharePreviewTitle: String {
        let title = liveSubscription.title.isEmpty
            ? (liveSubscription.feedURL.host ?? "Podcast")
            : liveSubscription.title
        return liveSubscription.author.isEmpty
            ? title
            : "\(title) by \(liveSubscription.author)"
    }

    // MARK: - Filtering

    private func filteredEpisodes() -> [Episode] {
        switch filter {
        case .all:
            return episodes
        case .unplayed:
            return episodes.filter { $0.isUnplayed || $0.isInProgress }
        case .downloaded:
            return episodes.filter {
                if case .downloaded = $0.downloadState { return true }
                return false
            }
        case .transcribed:
            return episodes.filter {
                if case .ready = $0.transcriptState { return true }
                return false
            }
        }
    }

    // MARK: - Actions

    private func confirmUnsubscribe() {
        showUnsubscribeConfirm = true
    }

    private func performUnsubscribe() {
        store.removeSubscription(subscription.id)
        dismiss()
    }

    private func refresh() async {
        await SubscriptionService(store: store).refresh(liveSubscription)
    }
}

// MARK: - ShowDetailSettingsSheet

/// "Settings for this show" sheet. Real toggles for notifications, the
/// per-show auto-download policy, and a destructive unsubscribe action.
struct ShowDetailSettingsSheet: View {
    let subscription: PodcastSubscription
    let store: AppStateStore
    let onDismiss: () -> Void
    let onUnsubscribe: () -> Void

    @State private var notificationsEnabled: Bool
    @State private var autoDownloadChoice: AutoDownloadChoice
    @State private var latestNCount: Int
    @State private var wifiOnly: Bool

    /// Picker-friendly enum that flattens `AutoDownloadPolicy.Mode`'s
    /// associated value into a stepper-driven count. `latestN` covers the
    /// "keep the most recent N" case; the count is held in a separate
    /// `@State` so the picker selection stays clean and the stepper is only
    /// shown when the user picks `latestN`.
    enum AutoDownloadChoice: String, CaseIterable, Identifiable {
        case off
        case latestN
        case allNew

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off:     return "Off"
            case .latestN: return "Latest"
            case .allNew:  return "All new"
            }
        }
    }

    init(
        subscription: PodcastSubscription,
        store: AppStateStore,
        onDismiss: @escaping () -> Void,
        onUnsubscribe: @escaping () -> Void
    ) {
        self.subscription = subscription
        self.store = store
        self.onDismiss = onDismiss
        self.onUnsubscribe = onUnsubscribe
        _notificationsEnabled = State(initialValue: subscription.notificationsEnabled)
        let policy = subscription.autoDownload
        switch policy.mode {
        case .off:
            _autoDownloadChoice = State(initialValue: .off)
            _latestNCount = State(initialValue: 5)
        case .latestN(let n):
            _autoDownloadChoice = State(initialValue: .latestN)
            _latestNCount = State(initialValue: n)
        case .allNew:
            _autoDownloadChoice = State(initialValue: .allNew)
            _latestNCount = State(initialValue: 5)
        }
        _wifiOnly = State(initialValue: policy.wifiOnly)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Notify me when new episodes drop", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            store.setSubscriptionNotificationsEnabled(
                                subscription.id,
                                enabled: newValue
                            )
                        }
                }
                Section("Auto-download") {
                    Picker("New episodes", selection: $autoDownloadChoice) {
                        ForEach(AutoDownloadChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: autoDownloadChoice) { _, _ in persistPolicy() }

                    if autoDownloadChoice == .latestN {
                        // `onEditingChanged` only fires on press-and-hold to
                        // auto-repeat — single taps on + / - update the
                        // binding but won't trip the closure. Use `.onChange`
                        // on the count instead so every value change persists.
                        Stepper(value: $latestNCount, in: 1...50) {
                            HStack {
                                Text("Keep latest")
                                Spacer()
                                Text("\(latestNCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .onChange(of: latestNCount) { _, _ in persistPolicy() }
                    }

                    if autoDownloadChoice != .off {
                        Toggle("Wi-Fi only", isOn: $wifiOnly)
                            .onChange(of: wifiOnly) { _, _ in persistPolicy() }
                    }
                }
                Section("Feed") {
                    LabeledContent("URL") {
                        Text(subscription.feedURL.absoluteString)
                            .font(AppTheme.Typography.monoCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    if let refreshed = subscription.lastRefreshedAt {
                        LabeledContent("Last refreshed") {
                            Text(refreshed.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        onDismiss()
                        onUnsubscribe()
                    } label: {
                        Label("Unsubscribe", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle(subscription.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Composes the three sheet-local fields back into the canonical
    /// `AutoDownloadPolicy` and writes through the store. Called from every
    /// path that mutates one of the inputs — keeping all the round-trip
    /// logic in one place avoids drift between the picker and the stepper.
    private func persistPolicy() {
        let mode: AutoDownloadPolicy.Mode
        switch autoDownloadChoice {
        case .off:     mode = .off
        case .latestN: mode = .latestN(latestNCount)
        case .allNew:  mode = .allNew
        }
        store.setSubscriptionAutoDownload(
            subscription.id,
            policy: AutoDownloadPolicy(mode: mode, wifiOnly: wifiOnly)
        )
    }
}
