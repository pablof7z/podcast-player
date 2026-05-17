import SwiftUI

struct RelayStatusBadge: View {
    let state: RelayConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.color)
                .frame(width: 7, height: 7)
            Text(state.label)
                .font(AppTheme.Typography.caption2.weight(.semibold))
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.color.opacity(0.12), in: Capsule())
    }
}

struct RelayRoleChip: View {
    let role: RelayRoleViewModel

    var body: some View {
        Label(role.rawValue, systemImage: role.icon)
            .font(AppTheme.Typography.caption2.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

struct RelayRowView: View {
    let relay: RelayViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(relay.state.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 6) {
                Text(relay.displayURL)
                    .font(AppTheme.Typography.callout.weight(.medium))
                    .lineLimit(1)
                    .truncatedMiddle()

                roleChips

                if let status = relay.statusDetail {
                    Text(status)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
            counters
        }
        .padding(.vertical, 4)
    }

    private var roleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(relay.sortedRoles) { role in
                    RelayRoleChip(role: role)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var counters: some View {
        VStack(alignment: .trailing, spacing: 4) {
            counter("\(relay.activeSubscriptions.count)", icon: "antenna.radiowaves.left.and.right")
            counter("\(relay.stats.messagesReceived)", icon: "arrow.down.circle")
            counter("\(relay.stats.messagesSent)", icon: "arrow.up.circle")
        }
        .foregroundStyle(.secondary)
        .font(AppTheme.Typography.caption2.monospacedDigit())
        .accessibilityLabel(
            "\(relay.activeSubscriptions.count) subscriptions, \(relay.stats.messagesReceived) received, \(relay.stats.messagesSent) sent"
        )
    }

    private var statusColor: Color {
        if case .failed = relay.state {
            return .red
        }
        return .secondary
    }

    private func counter(_ value: String, icon: String) -> some View {
        Label(value, systemImage: icon)
            .labelStyle(.titleAndIcon)
    }
}

struct RelaySubscriptionRowView: View {
    let subscription: RelaySubscriptionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(subscription.id)
                    .font(AppTheme.Typography.caption.monospaced())
                    .lineLimit(1)
                    .truncatedMiddle()
                Spacer(minLength: 8)
                Text("\(subscription.eventCount)")
                    .font(AppTheme.Typography.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !subscription.filterSummary.isEmpty {
                Text(subscription.filterSummary)
                    .font(AppTheme.Typography.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if !subscription.kinds.isEmpty {
                    Text("kinds \(subscription.kinds.map(String.init).joined(separator: ", "))")
                }
                Text("opened \(RelayDiagnosticsFormatters.relative(subscription.createdAt))")
                if let last = subscription.lastEventAt {
                    Text("last event \(RelayDiagnosticsFormatters.relative(last))")
                }
            }
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

struct RelayActivityLineRowView: View {
    let line: RelayActivityLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timestamp)
                .font(AppTheme.Typography.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 74, alignment: .leading)
            Text(line.message)
                .font(AppTheme.Typography.caption.monospaced())
                .foregroundStyle(line.level.color)
                .lineLimit(4)
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
    }

    private var timestamp: String {
        guard let date = line.timestamp else { return "--" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

enum RelayDiagnosticsFormatters {
    static func bytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(value))
    }

    static func latency(_ value: TimeInterval?) -> String {
        guard let value else { return "n/a" }
        return "\(Int((value * 1_000).rounded())) ms"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "n/a" }
        return date.formatted(.relative(presentation: .named))
    }
}
