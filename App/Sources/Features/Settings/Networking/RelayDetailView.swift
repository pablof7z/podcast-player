import SwiftUI

struct RelayDetailView: View {
    @Environment(AppStateStore.self) private var store
    @State private var relay: RelayViewModel

    init(initialRelay: RelayViewModel) {
        _relay = State(initialValue: initialRelay)
    }

    var body: some View {
        List {
            stateCard
            statisticsSection
            connectionSection
            rolesSection
            subscriptionsSection
            relayInfoSection
            activitySection
        }
        .settingsListStyle()
        .navigationTitle(relay.displayURL)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshLoop() }
        .refreshable { await refresh() }
    }

    private var stateCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    RelayStatusBadge(state: relay.state)
                    Spacer()
                    Text(relay.source)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                detailRow("Subscriptions", value: "\(relay.activeSubscriptions.count)")
                detailRow("Messages received", value: "\(relay.stats.messagesReceived)")
                detailRow("Messages sent", value: "\(relay.stats.messagesSent)")
                detailRow("Latency", value: RelayDiagnosticsFormatters.latency(relay.stats.latency))
                if let status = relay.statusDetail {
                    Divider()
                    detailRow("Status detail", value: status)
                        .foregroundStyle(statusColor)
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var statisticsSection: some View {
        Section("Statistics") {
            detailRow("Bytes received", value: RelayDiagnosticsFormatters.bytes(relay.stats.bytesReceived))
            detailRow("Bytes sent", value: RelayDiagnosticsFormatters.bytes(relay.stats.bytesSent))
            detailRow("Connection attempts", value: "\(relay.stats.connectionAttempts)")
            detailRow("Successful connects", value: "\(relay.stats.successfulConnections)")
            detailRow("Validated signatures", value: "\(relay.stats.validatedSignatures)")
            detailRow("Skipped signature checks", value: "\(relay.stats.skippedSignatureChecks)")
            detailRow("Signature verification", value: relay.stats.signatureVerificationEnabled ? "On" : "Off")
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            detailRow("URL", value: relay.url, monospaced: true)
            detailRow("Managed by NDK", value: relay.managedByNDK ? "Yes" : "No")
            detailRow("Authenticated", value: relay.authenticated ? "Yes" : "No")
            detailRow("Connected at", value: RelayDiagnosticsFormatters.relative(relay.stats.connectedAt))
            detailRow("Last message", value: RelayDiagnosticsFormatters.relative(relay.stats.lastMessageAt))
            detailRow("Last activity", value: RelayDiagnosticsFormatters.relative(relay.stats.lastActivityAt))
        }
    }

    private var rolesSection: some View {
        Section("Roles") {
            ForEach(relay.sortedRoles) { role in
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

    private var subscriptionsSection: some View {
        Section {
            if relay.activeSubscriptions.isEmpty {
                Text("No active subscriptions")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(relay.activeSubscriptions) { subscription in
                    RelaySubscriptionRowView(subscription: subscription)
                }
            }
        } header: {
            Text("Active Subscriptions")
        } footer: {
            Text("These are the live REQ filters currently tracked on this relay by NDKSwift.")
        }
    }

    @ViewBuilder
    private var relayInfoSection: some View {
        if let info = relay.relayInfo {
            Section("Relay Info") {
                if let name = info.name, !name.isEmpty {
                    detailRow("Name", value: name)
                }
                if let software = info.software, !software.isEmpty {
                    detailRow("Software", value: [software, info.version].compactMap { $0 }.joined(separator: " "))
                }
                if let contact = info.contact, !contact.isEmpty {
                    detailRow("Contact", value: contact)
                }
                if !info.supportedNips.isEmpty {
                    detailRow(
                        "Supported NIPs",
                        value: info.supportedNips.sorted().map(String.init).joined(separator: ", ")
                    )
                }
                if let limitation = info.limitation {
                    relayLimits(limitation)
                }
                if let description = info.description, !description.isEmpty {
                    Text(description)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var activitySection: some View {
        Section {
            ForEach(relay.activityLines) { line in
                RelayActivityLineRowView(line: line)
            }
        } header: {
            HStack {
                Text("Recent Activity")
                Spacer()
                Text("live")
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func relayLimits(_ limitation: RelayLimitationViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let maxSubscriptions = limitation.maxSubscriptions {
                detailRow("Max subscriptions", value: "\(maxSubscriptions)")
            }
            if let maxFilters = limitation.maxFilters {
                detailRow("Max filters", value: "\(maxFilters)")
            }
            if let maxLimit = limitation.maxLimit {
                detailRow("Max query limit", value: "\(maxLimit)")
            }
            if let maxMessageLength = limitation.maxMessageLength {
                detailRow(
                    "Max message",
                    value: RelayDiagnosticsFormatters.bytes(maxMessageLength)
                )
            }
            if limitation.authRequired == true {
                detailRow("Relay auth", value: "Required")
            }
            if limitation.paymentRequired == true {
                detailRow("Payment", value: "Required")
            }
            if limitation.restrictedWrites == true {
                detailRow("Writes", value: "Restricted")
            }
        }
    }

    private func detailRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? AppTheme.Typography.monoCaption : AppTheme.Typography.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var statusColor: Color {
        if case .failed = relay.state {
            return .red
        }
        return .secondary
    }

    private func refreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }
    }

    private func refresh() async {
        let snapshot = await RelayDiagnosticsProvider.load(store: store)
        guard let updated = snapshot.relays.first(where: { $0.id == relay.id }) else { return }
        relay = updated
    }
}

#Preview {
    NavigationStack {
        RelayDetailView(initialRelay: .configured(
            url: "wss://relay.tenex.chat",
            roles: [.inbox, .feedback, .profile],
            source: "Preview",
            statusDetail: "Configured, but not currently connected."
        ))
        .environment(AppStateStore())
    }
}
