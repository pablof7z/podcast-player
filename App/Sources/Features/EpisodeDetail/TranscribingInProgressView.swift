import SwiftUI

// MARK: - TranscribingInProgressView

/// Empty / in-progress state for the transcript surface.
///
/// Until the transcript ingestion lane lands we render a calm "not yet
/// available" panel for any non-`.ready` `transcriptState`. The view inspects
/// the state and chooses an appropriate copy + indicator (idle, queued,
/// fetching publisher, mid-Scribe progress, or failed).
///
/// "Request transcript" is intentionally disabled — once the ingestion lane
/// merges, the parent will swap in the real action.
struct TranscribingInProgressView: View {
    let episode: Episode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                header
                Divider()
                    .background(Color.secondary.opacity(0.2))
                    .padding(.horizontal, AppTheme.Spacing.md)
                copyBlock
                cta
            }
            .padding(.vertical, AppTheme.Spacing.xl)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("Transcript")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var header: some View {
        switch episode.transcriptState {
        case .transcribing(let progress):
            HStack(spacing: AppTheme.Spacing.md) {
                ProgressView(value: max(0, min(progress, 1)))
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        case .queued, .fetchingPublisher:
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView()
                Text(headerLabel)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, AppTheme.Spacing.md)
        case .none, .ready:
            EmptyView()
        }
    }

    private var headerLabel: String {
        switch episode.transcriptState {
        case .queued: return "Queued for transcription"
        case .fetchingPublisher: return "Fetching publisher transcript"
        default: return ""
        }
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(primaryCopy)
                .font(.system(.title3, design: .serif).weight(.medium))
                .foregroundStyle(.primary)
            Text(secondaryCopy)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private var primaryCopy: String {
        switch episode.transcriptState {
        case .none: return "Transcripts coming soon for this episode."
        case .queued: return "We've got this episode in the queue."
        case .fetchingPublisher: return "Pulling the publisher's transcript."
        case .transcribing: return "We're transcribing this episode now."
        case .failed: return "Transcription couldn't finish."
        case .ready: return "Transcript ready."
        }
    }

    private var secondaryCopy: String {
        switch episode.transcriptState {
        case .none:
            return "When the transcript ingestion lane lands you'll be able to read along, search, and pull quote cards from this view."
        case .queued, .fetchingPublisher, .transcribing:
            return "We'll surface the text here as soon as it's ready. You can keep listening while it processes."
        case .failed(let message):
            return message
        case .ready:
            return ""
        }
    }

    private var cta: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                // Disabled — transcript ingestion lane owns this action.
            } label: {
                Text("Request transcript")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .padding(.horizontal, AppTheme.Spacing.md)

            Text(footerLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footerLabel: String {
        if episode.publisherTranscriptURL != nil {
            return "Publisher transcript available"
        }
        return "Available once the transcript service is online"
    }
}

// MARK: - Preview

#Preview("Idle") {
    let subID = UUID()
    let episode = Episode(
        subscriptionID: subID,
        guid: "preview-1",
        title: "How to Think About Keto",
        pubDate: Date(),
        enclosureURL: URL(string: "https://traffic.megaphone.fm/HSW1234567890.mp3")!,
        transcriptState: .none
    )
    return NavigationStack { TranscribingInProgressView(episode: episode) }
}

#Preview("Transcribing") {
    let subID = UUID()
    let episode = Episode(
        subscriptionID: subID,
        guid: "preview-2",
        title: "How to Think About Keto",
        pubDate: Date(),
        enclosureURL: URL(string: "https://traffic.megaphone.fm/HSW1234567890.mp3")!,
        transcriptState: .transcribing(progress: 0.42)
    )
    return NavigationStack { TranscribingInProgressView(episode: episode) }
}
