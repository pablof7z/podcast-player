import SwiftUI

// MARK: - Episode row lifecycle surfaces

/// Quiet, read-only lifecycle text for episode rows.
///
/// This intentionally renders as metadata instead of a badge: the row should
/// explain what is happening without competing with the title or artwork.
struct EpisodeRowLifecycleLine: View {
    let episode: Episode
    let accent: Color

    var body: some View {
        if let render = EpisodeRowLifecycleRender(episode: episode, accent: accent) {
            HStack(spacing: 6) {
                ForEach(Array(render.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Circle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 3, height: 3)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 12, height: 12)
                        Text(item.label)
                            .font(AppTheme.Typography.caption2)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(item.tint)
                }
            }
            .minimumScaleFactor(0.9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(render.accessibilityLabel)
            .transition(.opacity)
            .animation(AppTheme.Animation.easeOut, value: render.animationKey)
        }
    }
}

/// Thin progress rail for the bottom edge of an `EpisodeRow`.
///
/// Determinate progress changes animate across snapshot jumps, so a kernel
/// update from 6% to 75% reads as movement instead of a sudden layout snap.
struct EpisodeRowProgressRail: View {
    let episode: Episode
    let accent: Color

    var body: some View {
        if let render = EpisodeRowProgressRender(episode: episode, accent: accent) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(render.track)
                        .frame(height: 2)

                    Capsule(style: .continuous)
                        .fill(render.fill)
                        .frame(width: render.width(in: geo.size.width), height: 2)
                        .animation(
                            SwiftUI.Animation.easeInOut(duration: 0.7),
                            value: render.animationValue
                        )
                }
            }
            .frame(height: 2)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Render models

private struct EpisodeRowLifecycleRender {
    let items: [EpisodeRowLifecycleItem]
    let accessibilityLabel: String
    let animationKey: String

    init?(episode: Episode, accent: Color) {
        var items: [EpisodeRowLifecycleItem] = []
        let transcript = Self.transcriptItem(for: episode.transcriptState)
        if let download = Self.downloadItem(
            for: episode.downloadState,
            accent: accent,
            showCompleted: transcript != nil
        ) {
            items.append(download)
        }
        if let transcript {
            items.append(transcript)
        }
        guard !items.isEmpty else { return nil }

        self.items = items
        self.accessibilityLabel = items
            .map(\.accessibilityLabel)
            .joined(separator: ", ")
        self.animationKey = items
            .map { "\($0.id):\($0.label)" }
            .joined(separator: "|")
    }

    private static func downloadItem(
        for state: DownloadState,
        accent: Color,
        showCompleted: Bool
    ) -> EpisodeRowLifecycleItem? {
        switch state {
        case .notDownloaded:
            return nil
        case .queued:
            return EpisodeRowLifecycleItem(
                id: "download",
                symbol: "clock",
                label: "Waiting to download",
                tint: accent,
                accessibilityLabel: "Download waiting to start"
            )
        case .downloading(let progress, _):
            let pct = Int((progress.clamped01 * 100).rounded())
            return EpisodeRowLifecycleItem(
                id: "download",
                symbol: "arrow.down.circle.fill",
                label: "Downloading \(pct)%",
                tint: accent,
                accessibilityLabel: "Downloading \(pct) percent"
            )
        case .downloaded:
            guard showCompleted else { return nil }
            return EpisodeRowLifecycleItem(
                id: "download",
                symbol: "checkmark.circle.fill",
                label: "Downloaded",
                tint: .secondary,
                accessibilityLabel: "Downloaded"
            )
        case .failed:
            return EpisodeRowLifecycleItem(
                id: "download",
                symbol: "exclamationmark.triangle.fill",
                label: "Download failed",
                tint: AppTheme.Tint.error,
                accessibilityLabel: "Download failed"
            )
        }
    }

    private static func transcriptItem(for state: TranscriptState) -> EpisodeRowLifecycleItem? {
        switch state {
        case .none:
            return nil
        case .queued:
            return EpisodeRowLifecycleItem(
                id: "transcript",
                symbol: "text.bubble",
                label: "Transcript waiting",
                tint: .secondary,
                accessibilityLabel: "Transcript waiting"
            )
        case .fetchingPublisher:
            return EpisodeRowLifecycleItem(
                id: "transcript",
                symbol: "doc.text.magnifyingglass",
                label: "Fetching transcript",
                tint: AppTheme.Tint.agentSurface,
                accessibilityLabel: "Fetching transcript"
            )
        case .transcribing(let progress):
            let pct = Int((progress.clamped01 * 100).rounded())
            let label = pct > 0 ? "Transcribing \(pct)%" : "Transcribing"
            let accessibility = pct > 0 ? "Transcribing \(pct) percent" : "Transcribing"
            return EpisodeRowLifecycleItem(
                id: "transcript",
                symbol: "waveform",
                label: label,
                tint: AppTheme.Tint.agentSurface,
                accessibilityLabel: accessibility
            )
        case .ready:
            return EpisodeRowLifecycleItem(
                id: "transcript",
                symbol: "text.bubble.fill",
                label: "Transcript ready",
                tint: AppTheme.Tint.success,
                accessibilityLabel: "Transcript ready"
            )
        case .failed:
            return EpisodeRowLifecycleItem(
                id: "transcript",
                symbol: "exclamationmark.bubble.fill",
                label: "Transcript failed",
                tint: AppTheme.Tint.error,
                accessibilityLabel: "Transcript failed"
            )
        }
    }
}

private struct EpisodeRowLifecycleItem: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let tint: Color
    let accessibilityLabel: String
}

private struct EpisodeRowProgressRender {
    let fill: Color
    let track: Color
    let fraction: Double
    let minWidth: CGFloat
    let animationValue: Double

    init?(episode: Episode, accent: Color) {
        switch episode.downloadState {
        case .queued:
            self.fill = accent.opacity(0.5)
            self.track = accent.opacity(0.14)
            self.fraction = 0.22
            self.minWidth = 28
            self.animationValue = -1
        case .downloading(let progress, _):
            let clamped = progress.clamped01
            self.fill = accent
            self.track = accent.opacity(0.14)
            self.fraction = clamped
            self.minWidth = 8
            self.animationValue = clamped
        case .failed:
            self.fill = AppTheme.Tint.error.opacity(0.7)
            self.track = AppTheme.Tint.error.opacity(0.12)
            self.fraction = 1
            self.minWidth = 0
            self.animationValue = 1
        case .notDownloaded, .downloaded:
            guard let transcript = Self.transcriptRender(for: episode.transcriptState) else {
                return nil
            }
            self = transcript
        }
    }

    func width(in total: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let proposed = max(minWidth, total * fraction.clamped01)
        return min(total, proposed)
    }

    private static func transcriptRender(for state: TranscriptState) -> EpisodeRowProgressRender? {
        switch state {
        case .queued, .fetchingPublisher:
            return EpisodeRowProgressRender(
                fill: AppTheme.Tint.agentSurface.opacity(0.5),
                track: AppTheme.Tint.agentSurface.opacity(0.12),
                fraction: 0.22,
                minWidth: 28,
                animationValue: -2
            )
        case .transcribing(let progress):
            let clamped = progress.clamped01
            let hasProgress = clamped > 0.005
            return EpisodeRowProgressRender(
                fill: AppTheme.Tint.agentSurface,
                track: AppTheme.Tint.agentSurface.opacity(0.12),
                fraction: hasProgress ? clamped : 0.22,
                minWidth: hasProgress ? 8 : 28,
                animationValue: hasProgress ? clamped : -3
            )
        case .none, .ready, .failed:
            return nil
        }
    }

    private init(
        fill: Color,
        track: Color,
        fraction: Double,
        minWidth: CGFloat,
        animationValue: Double
    ) {
        self.fill = fill
        self.track = track
        self.fraction = fraction
        self.minWidth = minWidth
        self.animationValue = animationValue
    }
}
