import SwiftUI

// MARK: - PlayerTranscriptRow

/// Single transcript line as it appears inside the dark-chrome player surface.
///
/// Visual priorities differ from `TranscriptReaderView`'s row:
///   - Light text on a dark wallpaper (white at varying opacity, not
///     `.primary`).
///   - Active line gets a gentle white underlay rather than the editorial
///     yellow tint — yellow over the player wallpaper would clash with the
///     hero artwork.
///   - Speaker label sits inline as a small uppercase chip above the line,
///     so consecutive same-speaker rows stay visually packed without a
///     full paragraph re-render.
struct PlayerTranscriptRow: View {

    let segment: Segment
    let speaker: Speaker?
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let speakerName {
                Text(speakerName.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(isActive ? 0.92 : 0.50))
            }
            Text(segment.text)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(isActive ? 0.18 : 0), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// Display name with a graceful fallback to the raw label so we never
    /// show "Unknown" — the source label is at least a stable identifier.
    private var speakerName: String? {
        guard let speaker else { return nil }
        return speaker.displayName ?? speaker.label
    }

    private var accessibilityText: String {
        if let speakerName {
            return "\(speakerName), \(segment.text)"
        }
        return segment.text
    }
}
