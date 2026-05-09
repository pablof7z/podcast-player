import SwiftUI

// MARK: - EpisodeDetailHeroView

/// Magazine-cover layout for an episode in `.detail` mode (UX-03 §6.1):
/// hero artwork + title block, action row, italic summary lede, chapter
/// list, show-notes prose, and the "Read transcript" CTA.
///
/// Extracted from `EpisodeDetailView` to keep that file under the 300-line
/// soft limit. Owns no state; all interactions bubble up via callbacks.
struct EpisodeDetailHeroView: View {
    let episode: MockEpisode
    let onPlayChapter: (MockEpisode.Chapter) -> Void
    let onReadTranscript: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                hero
                actionRow
                summarySection
                chaptersSection
                showNotesSection
                readTranscriptCTA
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title.uppercased())
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                Text(episode.showName)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
            .fill(LinearGradient(
                colors: [Color.orange.opacity(0.65), Color.purple.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: 110, height: 110)
            .overlay(
                Text(String(episode.showName.prefix(1)))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            )
    }

    private var metadataLine: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let date = f.string(from: episode.publishedAt)
        let mins = Int(episode.duration / 60)
        return "#\(episode.episodeNumber.map(String.init) ?? "—") · \(date) · \(mins / 60)h \(mins % 60)m"
    }

    // MARK: Sections

    private var actionRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            actionPill("Play", systemImage: "play.fill")
            actionPill("Download", systemImage: "arrow.down.circle")
            actionPill("Save", systemImage: "plus.circle")
        }
    }

    private func actionPill(_ label: String, systemImage: String) -> some View {
        Button { } label: {
            Label(label, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassSurface(cornerRadius: AppTheme.Corner.pill, interactive: true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionDivider("Summary")
            Text("\u{201C}\(episode.summary)\u{201D}")
                .font(.system(size: 21, weight: .medium, design: .serif).italic())
                .lineSpacing(8)
                .foregroundStyle(.primary)
        }
    }

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionDivider("Chapters")
            ForEach(episode.chapters) { chapter in
                Button {
                    onPlayChapter(chapter)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatTimestamp(chapter.start))
                            .font(.system(.footnote, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        Text(chapter.title)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var showNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionDivider("Show notes")
            Text(strippedShowNotes)
                .font(.system(size: 17, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(.secondary)
        }
    }

    private var readTranscriptCTA: some View {
        Button(action: onReadTranscript) {
            Text("Read transcript")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: Helpers

    private func sectionDivider(_ label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 18, height: 1)
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
        }
        .padding(.top, 8)
    }

    /// Naive HTML strip — Lane 2 will swap in an attributed renderer.
    private var strippedShowNotes: String {
        var inTag = false
        var out = ""
        for c in episode.showNotesHTML {
            if c == "<" { inTag = true; continue }
            if c == ">" { inTag = false; continue }
            if !inTag { out.append(c) }
        }
        return out.replacingOccurrences(of: "  ", with: " ")
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
