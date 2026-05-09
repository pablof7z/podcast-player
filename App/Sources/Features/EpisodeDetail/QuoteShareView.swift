import SwiftUI

// MARK: - QuoteShareView

/// Exportable quote card per UX-03 §6.5. Used inside a SwiftUI sheet; the
/// rendered card can be passed to `ImageRenderer` for image export.
///
/// Three actions: image, audio+sub, link. Wiring lives one level up — this
/// view is just the visual.
struct QuoteShareView: View {
    let episode: MockEpisode
    let segment: Segment
    let speaker: Speaker?
    let deepLink: String

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            card
                .frame(maxWidth: 360)
            actionRow
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.showName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("#\(episode.episodeNumber.map(String.init) ?? "—") · \(formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("“\(segment.text)”")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("— \(speaker?.displayName ?? speaker?.label ?? "Unknown"), \(formattedTimestamp)")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(deepLink)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 24, y: 8)
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
            .fill(LinearGradient(
                colors: [Color.orange.opacity(0.7), Color.purple.opacity(0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: 44, height: 44)
            .overlay(
                Text(String(episode.showName.prefix(1)))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            )
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: episode.publishedAt)
    }

    private var formattedTimestamp: String {
        let total = Int(segment.start)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            actionButton(label: "Image", systemImage: "photo")
            actionButton(label: "Audio + Sub", systemImage: "waveform")
            actionButton(label: "Link", systemImage: "link")
        }
    }

    private func actionButton(label: String, systemImage: String) -> some View {
        Button {
            // Hooked up by the parent surface.
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

// MARK: - Preview

#Preview {
    let (episode, transcript) = MockEpisodeFixture.timFerrissKeto()
    let segment = transcript.segments.first(where: { !$0.text.hasPrefix("[") })!
    return QuoteShareView(
        episode: episode,
        segment: segment,
        speaker: transcript.speaker(for: segment.speakerID),
        deepLink: "podcast.app/e/\(episode.episodeNumber ?? 0)?t=\(Int(segment.start))"
    )
}
