import SwiftUI
import UserNotifications
import os.log

// MARK: - NotificationSettingsView
//
// Settings → Notifications. Shows the current authorization status and the
// full list of pending reminder notifications. Users can cancel individual
// reminders with a swipe or tap "Open Settings" when permission is denied.
//
// Data is loaded async from UNUserNotificationCenter; only requests whose
// identifiers start with the "reminder:" prefix (managed by NotificationService)
// are shown. Each request is matched to its live Item so we can show the
// item title rather than the raw notification body.

struct NotificationSettingsView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.openURL) private var openURL

    private static let logger = Logger.app("NotificationSettingsView")

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingReminders: [PendingReminder] = []
    @State private var isLoading = true
    @State private var showCancelAllConfirm = false

    /// Reminders grouped by relative-date bucket (Today / Tomorrow / This Week / Later).
    private var groupedReminders: [(bucket: ReminderDateBucket, reminders: [PendingReminder])] {
        let now = Date()
        let calendar = Calendar.current
        var dict: [ReminderDateBucket: [PendingReminder]] = [:]
        for reminder in pendingReminders {
            let key = ReminderDateBucket.bucket(for: reminder.fireDate, now: now, calendar: calendar)
            dict[key, default: []].append(reminder)
        }
        return ReminderDateBucket.allCases.compactMap { bucket in
            guard let reminders = dict[bucket], !reminders.isEmpty else { return nil }
            return (bucket, reminders)
        }
    }

    var body: some View {
        List {
            permissionSection
            if authStatus != .denied {
                remindersSection
            }
        }
        .settingsListStyle()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .toolbar {
            if pendingReminders.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel All", role: .destructive) {
                        showCancelAllConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(
            "Cancel All Reminders?",
            isPresented: $showCancelAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel \(pendingReminders.count) Reminders", role: .destructive) {
                cancelAll()
            }
            Button("Keep Reminders", role: .cancel) {}
        } message: {
            Text("This will remove all \(pendingReminders.count) scheduled reminders. You can set new ones from item detail views.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var permissionSection: some View {
        Section("Status") {
            switch authStatus {
            case .authorized, .provisional, .ephemeral:
                SettingsRow(
                    icon: "bell.badge.fill",
                    tint: .green,
                    title: "Reminders allowed",
                    subtitle: "You'll be notified when items are due"
                )
            case .denied:
                SettingsRow(
                    icon: "bell.slash.fill",
                    tint: .red,
                    title: "Notifications blocked",
                    subtitle: "Enable in iOS Settings to receive reminders"
                )
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    SettingsRow(
                        icon: "gear",
                        tint: .blue,
                        title: "Open Settings"
                    )
                }
                .foregroundStyle(.primary)
            case .notDetermined:
                SettingsRow(
                    icon: "bell",
                    tint: .secondary,
                    title: "Not yet requested",
                    subtitle: "Grant access so the app can deliver reminders"
                )
                AsyncButton {
                    await requestPermission()
                } label: {
                    SettingsRow(
                        icon: "bell.badge",
                        tint: .orange,
                        title: "Request Permission"
                    )
                }
                .foregroundStyle(.primary)
            @unknown default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        if isLoading {
            Section("Scheduled Reminders") {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        } else if pendingReminders.isEmpty {
            Section("Scheduled Reminders") {
                ContentUnavailableView {
                    Label("No pending reminders", systemImage: "bell.slash")
                } description: {
                    Text("Set a reminder when adding or editing an item.")
                }
                .listRowBackground(Color.clear)
            }
        } else {
            ForEach(groupedReminders, id: \.bucket) { group in
                Section {
                    ForEach(group.reminders) { reminder in
                        reminderRow(reminder)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    cancel(reminder)
                                } label: {
                                    Label("Cancel", systemImage: "bell.slash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(group.bucket.rawValue)
                        Spacer()
                        Text("\(group.reminders.count)")
                            .monospacedDigit()
                    }
                }
            }
            Section {
            } footer: {
                Text("\(pendingReminders.count) reminder\(pendingReminders.count == 1 ? "" : "s") pending · Swipe left to cancel.")
            }
        }
    }

    // MARK: - Row

    private func reminderRow(_ reminder: PendingReminder) -> some View {
        SettingsRow(
            icon: "bell.fill",
            tint: .orange,
            title: reminder.title,
            subtitle: reminder.fireDate.shortDateTime,
            value: reminder.fireDate > Date()
                ? reminder.fireDate.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
                : nil
        )
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    // MARK: - Data

    private func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            authStatus = granted ? .authorized : .denied
            Haptics.selection()
        } catch {
            Self.logger.error("requestAuthorization failed: \(error, privacy: .public)")
        }
        await reload()
    }

    private func reload() async {
        isLoading = true
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let requests = await center.pendingNotificationRequests()

        authStatus = settings.authorizationStatus

        let items = store.state.items

        let mapped: [PendingReminder] = requests
            .filter { $0.identifier.hasPrefix(NotificationService.reminderIDPrefix) }
            .compactMap { request -> PendingReminder? in
                guard
                    let trigger = request.trigger as? UNCalendarNotificationTrigger,
                    let fireDate = trigger.nextTriggerDate()
                else { return nil }

                // Strip the "reminder:" prefix to get the UUID (or "UUID:wdN" for weekday fan-out).
                let rawSuffix = String(request.identifier.dropFirst(NotificationService.reminderIDPrefix.count))
                // Weekday fan-out identifiers are "<uuid>:wdN" — extract just the UUID portion.
                let uuidString = rawSuffix.contains(":wd")
                    ? String(rawSuffix.prefix(upTo: rawSuffix.range(of: ":wd")!.lowerBound))
                    : rawSuffix
                let itemUUID = UUID(uuidString: uuidString)
                let title: String
                if let uuid = itemUUID,
                   let item = items.first(where: { $0.id == uuid }) {
                    title = item.title
                } else {
                    // Fall back to the notification body if the item was deleted.
                    title = request.content.body
                }
                return PendingReminder(
                    id: request.identifier,
                    itemID: itemUUID,
                    title: title,
                    fireDate: fireDate
                )
            }

        // Weekday fan-out schedules 5 notifications per item — deduplicate by item UUID,
        // keeping only the one that fires soonest so the list shows one row per item.
        var seen: Set<UUID> = []
        pendingReminders = mapped
            .sorted { $0.fireDate < $1.fireDate }
            .filter { reminder in
                guard let uuid = reminder.itemID else { return true }
                return seen.insert(uuid).inserted
            }

        isLoading = false
    }

    private func cancelAll() {
        for reminder in pendingReminders {
            if let itemID = reminder.itemID {
                NotificationService.cancel(for: itemID)
                store.clearReminderDate(for: itemID)
            } else {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: [reminder.id])
            }
        }
        withAnimation(AppTheme.Animation.spring) {
            pendingReminders.removeAll()
        }
        Haptics.bulkAction()
    }

    private func cancel(_ reminder: PendingReminder) {
        if let itemID = reminder.itemID {
            NotificationService.cancel(for: itemID)
            // Clear the stored reminder date from the item so the edit sheet
            // doesn't show a stale picker value.
            store.clearReminderDate(for: itemID)
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [reminder.id])
        }
        withAnimation(AppTheme.Animation.spring) {
            pendingReminders.removeAll { $0.id == reminder.id }
        }
        Haptics.selection()
    }
}

