import SwiftUI
import UserNotifications
import os.log

// MARK: - NotificationSettingsView
//
// Settings → Notifications. Shows the current authorization status and lets
// the user open the system settings page to grant or revoke permission.
// (Pending-reminder management was removed along with the todo feature.)

struct NotificationSettingsView: View {
    @Environment(\.openURL) private var openURL

    nonisolated private static let logger = Logger.app("NotificationSettingsView")

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var isLoading = true

    var body: some View {
        List {
            permissionSection
        }
        .settingsListStyle()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthStatus() }
    }

    // MARK: - Sections

    private var permissionSection: some View {
        Section {
            HStack {
                Image(systemName: authStatus.iconName)
                    .foregroundStyle(authStatus.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authStatus.title)
                        .font(.body)
                    Text(authStatus.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if authStatus == .notDetermined {
                    Button("Allow") {
                        Task {
                            _ = await NotificationService.requestAuthorization()
                            await refreshAuthStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                } else if authStatus == .denied,
                          let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(url) }
                        .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Permission")
        } footer: {
            Text("Notifications are used for Nostr contact requests. Permission is requested on first use.")
        }
    }

    // MARK: - Loading

    private func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
        isLoading = false
    }
}

// MARK: - Auth status presentation

private extension UNAuthorizationStatus {
    var iconName: String {
        switch self {
        case .authorized, .provisional, .ephemeral: "bell.fill"
        case .denied: "bell.slash.fill"
        case .notDetermined: "bell"
        @unknown default: "bell"
        }
    }

    var tint: Color {
        switch self {
        case .authorized, .provisional, .ephemeral: .green
        case .denied: .red
        case .notDetermined: .secondary
        @unknown default: .secondary
        }
    }

    var title: String {
        switch self {
        case .authorized: "Allowed"
        case .provisional: "Allowed (Provisional)"
        case .ephemeral: "Allowed (Ephemeral)"
        case .denied: "Denied"
        case .notDetermined: "Not yet asked"
        @unknown default: "Unknown"
        }
    }

    var subtitle: String {
        switch self {
        case .authorized: "Notifications are enabled for this app."
        case .provisional: "Notifications are delivered quietly."
        case .ephemeral: "Notifications are temporary."
        case .denied: "Enable in iOS Settings to receive contact-request alerts."
        case .notDetermined: "We'll ask the first time something needs to notify you."
        @unknown default: ""
        }
    }
}
