import SwiftUI

// MARK: - ChaptersView
//
// Sheet-presented vertical list of chapters for one episode. Pure read of
// `EpisodeSummary.chapters` re-resolved from the live snapshot, so a
// `podcast.chapters.compile` dispatch that lands new chapters refreshes
// the list. Tapping a row dispatches `podcast.player.seek` (D7).

struct ChaptersView: View {
    let episodeId: String
    let podcastId: String?

    @Environment(KernelModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Chapters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let chapters = liveChapters
        if chapters.isEmpty {
            emptyState
        } else {
            List {
                ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                    ChapterRow(
                        index: index,
                        chapter: chapter,
                        isCurrent: isCurrent(at: index, in: chapters),
                        onTap: { seek(to: chapter.startSecs) }
                    )
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No chapters yet")
                .font(AppTheme.Typography.headline)
            Text("Generate chapters from the episode detail to see them here.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Re-resolve chapters from the snapshot so a `compile` dispatch that
    /// lands new chapters refreshes the list without re-pushing the view.
    private var liveChapters: [ChapterSummary] {
        guard let library = model.podcastSnapshot?.library else { return [] }
        let pool: [EpisodeSummary] = podcastId
            .flatMap { id in library.first(where: { $0.id == id })?.episodes }
            ?? library.flatMap { $0.episodes }
        return pool.first(where: { $0.id == episodeId })?.chapters ?? []
    }

    private var currentPositionSecs: Double {
        guard let np = model.podcastSnapshot?.nowPlaying,
              np.episodeId == episodeId else { return 0 }
        return np.positionSecs
    }

    private func isCurrent(at index: Int, in chapters: [ChapterSummary]) -> Bool {
        let now = currentPositionSecs
        let chapter = chapters[index]
        guard chapter.startSecs <= now else { return false }
        if let end = chapter.endSecs { return now < end }
        // No `endSecs` published — current iff the next chapter (if any)
        // hasn't started yet.
        let next = chapters.indices.contains(index + 1) ? chapters[index + 1] : nil
        return next.map { now < $0.startSecs } ?? true
    }

    private func seek(to secs: Double) {
        Haptics.medium()
        model.dispatch(
            namespace: "podcast.player",
            body: ["op": "seek", "position_secs": secs]
        )
    }
}

// MARK: - ChapterRow

private struct ChapterRow: View {
    let index: Int
    let chapter: ChapterSummary
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                artwork
                titleAndTime
                Spacer()
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Currently playing")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Seek to \(formatTimestamp(chapter.startSecs))")
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let url = chapter.imageUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholderArtwork
                    }
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous))
    }

    private var titleAndTime: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("\(index + 1).")
                    .font(AppTheme.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(chapter.title)
                    .font(AppTheme.Typography.headline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if chapter.isAiGenerated {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple)
                        .accessibilityLabel("AI generated chapter")
                }
            }
            Text(formatTimestamp(chapter.startSecs))
                .font(AppTheme.Typography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        let ai = chapter.isAiGenerated ? ", AI generated" : ""
        return "Chapter \(index + 1): \(chapter.title)\(ai)"
    }

    private func formatTimestamp(_ secs: Double) -> String {
        let total = max(0, Int(secs.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
