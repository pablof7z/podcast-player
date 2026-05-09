import SwiftUI

// MARK: - DownloadStatus

/// Compact value type describing the download / transcription state of an
/// episode for display in `EpisodeRow` and the Downloads section.
///
/// Lane 2 will replace this with the real per-episode state model; the
/// `case`s here mirror the visual states in ux-02 §6.B / §6.E so the
/// orchestrator can map directly at merge time.
enum DownloadStatus: Equatable, Hashable {
    /// Streaming-only — no local copy, no transcript work in flight.
    case none
    /// File downloaded; transcription either complete or not requested.
    case downloaded(transcribed: Bool)
    /// Download in progress.
    case downloading(progress: Double)
    /// Download complete; transcription job in flight.
    case transcribing(progress: Double)
    /// Download complete; queued for transcription behind other jobs.
    case transcriptionQueued(position: Int)
    /// Download or transcription failed; user can retry.
    case failed
}

// MARK: - DownloadStatusCapsule

/// Small reusable capsule — Liquid Glass T2 (structural glass) — used in
/// episode rows and the Downloads list to surface the three-axis status
/// (downloaded × transcribed × in-flight). Keep it short: capsule reads as
/// a one-line compound VoiceOver label, never two stacked chips.
///
/// **Glass usage:** This capsule is one of the *structural* surfaces
/// allowed by the lane brief (along with the OPML sheet and the filter
/// rail container). Cards stay matte; this little badge is the exception.
struct DownloadStatusCapsule: View {
    let status: DownloadStatus

    var body: some View {
        if let render = render {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: render.symbol)
                    .font(.caption2.weight(.semibold))
                Text(render.label)
                    .font(AppTheme.Typography.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, 4)
            .foregroundStyle(render.foreground)
            .glassEffect(
                .regular.tint(render.tint),
                in: .capsule
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(render.accessibilityLabel)
        }
    }

    // MARK: - Render

    private struct Render {
        let symbol: String
        let label: String
        let tint: Color
        let foreground: Color
        let accessibilityLabel: String
    }

    private var render: Render? {
        switch status {
        case .none:
            return nil
        case .downloaded(let transcribed):
            return Render(
                symbol: transcribed ? "text.bubble.fill" : "arrow.down.circle.fill",
                label: transcribed ? "Transcribed" : "Downloaded",
                tint: Color.green.opacity(0.18),
                foreground: .primary,
                accessibilityLabel: transcribed
                    ? "Downloaded, transcript available"
                    : "Downloaded"
            )
        case .downloading(let progress):
            let pct = Int((progress.clamped01 * 100).rounded())
            return Render(
                symbol: "arrow.down.circle",
                label: "Downloading \(pct)%",
                tint: Color.blue.opacity(0.20),
                foreground: .primary,
                accessibilityLabel: "Downloading \(pct) percent"
            )
        case .transcribing(let progress):
            let pct = Int((progress.clamped01 * 100).rounded())
            return Render(
                symbol: "waveform",
                label: "Transcribing \(pct)%",
                tint: AppTheme.Tint.agentSurface.opacity(0.20),
                foreground: .primary,
                accessibilityLabel: "Transcribing \(pct) percent"
            )
        case .transcriptionQueued(let position):
            return Render(
                symbol: "hourglass",
                label: "Queue #\(position)",
                tint: Color.orange.opacity(0.20),
                foreground: .primary,
                accessibilityLabel: "Queued for transcription, position \(position)"
            )
        case .failed:
            return Render(
                symbol: "exclamationmark.triangle.fill",
                label: "Failed",
                tint: AppTheme.Tint.error.opacity(0.22),
                foreground: .primary,
                accessibilityLabel: "Failed"
            )
        }
    }
}

// MARK: - Helpers

private extension Double {
    /// Clamp a progress fraction into `0...1` for safe display.
    var clamped01: Double { Swift.max(0, Swift.min(1, self)) }
}
