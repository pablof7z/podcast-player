import SwiftUI
import os.log

// MARK: - SubscriptionsListView
//
// Settings → Subscriptions. A management surface — distinct from the Library
// tab grid — that lets the user:
//   • see every show they're subscribed to,
//   • toggle per-show notifications,
//   • unsubscribe (with a confirmation),
//   • export the whole list as OPML via the system share sheet.
//
// Uses `store.sortedSubscriptions` so order matches the Library grid.

struct SubscriptionsListView: View {
    @Environment(AppStateStore.self) private var store

    nonisolated private static let logger = Logger.app("SubscriptionsListView")

    @State private var pendingDelete: PodcastSubscription?
    @State private var opmlURL: URL?
    @State private var showShareSheet: Bool = false
    @State private var exportError: String?

    var body: some View {
        List {
            if store.sortedSubscriptions.isEmpty {
                emptyStateSection
            } else {
                subscriptionsSection
            }
            exportSection
        }
        .settingsListStyle()
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Unsubscribe",
            isPresented: pendingDeleteBinding,
            presenting: pendingDelete
        ) { sub in
            Button("Unsubscribe", role: .destructive) {
                store.removeSubscription(sub.id)
                Haptics.success()
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { sub in
            Text("Remove \(sub.title) and all of its episodes from your library? This cannot be undone.")
        }
        .alert(
            "Couldn't export OPML",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            ),
            presenting: exportError
        ) { _ in
            Button("OK", role: .cancel) { exportError = nil }
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $showShareSheet) {
            if let opmlURL { ShareSheet(items: [opmlURL]) }
        }
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("No subscriptions yet")
                    .font(AppTheme.Typography.headline)
                Text("Add a podcast from the Library tab to get started.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }

    private var subscriptionsSection: some View {
        Section {
            ForEach(store.sortedSubscriptions) { sub in
                row(for: sub)
            }
        } header: {
            Text("\(store.sortedSubscriptions.count) show\(store.sortedSubscriptions.count == 1 ? "" : "s")")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                exportOPML()
            } label: {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    tint: .teal,
                    title: "Export OPML",
                    subtitle: "Share with another podcast app"
                )
            }
            .buttonStyle(.pressable)
            .disabled(store.sortedSubscriptions.isEmpty)
        } footer: {
            Text("Exports all subscribed feed URLs as a standard OPML 2.0 document.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for sub: PodcastSubscription) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.sm) {
                artwork(for: sub)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.title.isEmpty ? sub.feedURL.host ?? "Untitled" : sub.title)
                        .font(AppTheme.Typography.body)
                        .lineLimit(1)
                    if !sub.author.isEmpty {
                        Text(sub.author)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    // Status row: episode count + auto-download mode (when
                    // not Off). Surfaces here so a user managing many subs
                    // can see at a glance which feeds are pulling bytes
                    // automatically without diving into per-show settings.
                    statusRow(for: sub)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Toggle(isOn: notificationsBinding(for: sub)) {
                    Label("Episode alerts", systemImage: "bell.fill")
                        .font(AppTheme.Typography.caption)
                        .labelStyle(.titleAndIcon)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = sub
            } label: {
                Label("Unsubscribe", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func statusRow(for sub: PodcastSubscription) -> some View {
        let count = store.episodes(forSubscription: sub.id).count
        let countLabel = count == 1 ? "1 episode" : "\(count) episodes"
        HStack(spacing: 6) {
            Text(countLabel)
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let policy = sub.autoDownload.summaryLabel {
                Text("·")
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.tertiary)
                Label(policy, systemImage: "arrow.down.circle")
                    .labelStyle(StatusBadgeLabelStyle())
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.tint)
            }
        }
    }

    private func artwork(for sub: PodcastSubscription) -> some View {
        Group {
            if let url = sub.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.2))
            Image(systemName: "headphones")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func notificationsBinding(for sub: PodcastSubscription) -> Binding<Bool> {
        Binding(
            get: { store.subscription(id: sub.id)?.notificationsEnabled ?? sub.notificationsEnabled },
            set: { store.setSubscriptionNotificationsEnabled(sub.id, enabled: $0) }
        )
    }

    // MARK: - OPML export

    private func exportOPML() {
        let exporter = OPMLExport()
        let data = exporter.exportOPML(subscriptions: store.sortedSubscriptions)
        let filename = "Podcastr-Subscriptions-\(Self.dateStamp()).opml"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: [.atomic])
            opmlURL = url
            showShareSheet = true
            Haptics.success()
        } catch {
            Self.logger.error("OPML export write failed: \(error, privacy: .public)")
            exportError = error.localizedDescription
            Haptics.error()
        }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}

/// Compact horizontal label so the auto-download badge on the
/// subscriptions list reads as a single inline chip — default `Label`
/// stacks the icon at a heavier weight than this row needs.
private struct StatusBadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 9, weight: .semibold))
            configuration.title
        }
    }
}
