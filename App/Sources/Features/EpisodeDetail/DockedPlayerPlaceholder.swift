import SwiftUI

// MARK: - DockedPlayerPlaceholder

/// Minimal docked player pill — Lane 4 owns the real player. We only own
/// dock geometry per UX-03 §4 ("the player exposes `currentTime`,
/// `seek(to:)`, `presentationMode`"). Until Lane 4 lands, this placeholder
/// keeps EpisodeDetail visually complete.
struct DockedPlayerPlaceholder: View {
    let title: String
    let subtitle: String
    let currentTime: TimeInterval
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .lineLimit(1)
                    Text("·")
                    Text("\(format(currentTime)) / \(format(duration))")
                        .monospaced()
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "forward.end.fill")
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(
            cornerRadius: AppTheme.Corner.pill,
            tint: Color.orange.opacity(0.10),
            interactive: true
        )
    }

    private func format(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
