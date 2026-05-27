import SwiftUI

struct RelayRowView: View {
    let relayURL: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayHost)
                    .font(.body)
                Text(relayURL)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayHost: String {
        URL(string: relayURL)?.host ?? relayURL
    }
}

struct RelayStatusBadge: View {
    let isConnected: Bool

    var body: some View {
        Text(isConnected ? "Connected" : "Disconnected")
            .font(AppTheme.Typography.caption)
            .foregroundStyle(isConnected ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isConnected ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
            )
    }
}
