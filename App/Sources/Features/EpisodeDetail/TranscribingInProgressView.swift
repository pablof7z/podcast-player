import SwiftUI

// MARK: - TranscribingInProgressView

/// Distinctive state when ElevenLabs Scribe is mid-flight. Per UX-03 §6.4 we
/// stream the partial transcript in real-time and animate skeleton paragraphs
/// for the rest. ETA + provider attribution is shown inline.
struct TranscribingInProgressView: View {
    let episode: MockEpisode
    let partial: Transcript
    let progress: Double                 // 0…1, drives the percentage badge
    let etaMinutes: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                header
                Divider()
                    .background(Color.secondary.opacity(0.2))
                    .padding(.horizontal, AppTheme.Spacing.md)
                liveBlock
                skeletonBlock
                cta
            }
            .padding(.vertical, AppTheme.Spacing.xl)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("Transcribing…")
    }

    // MARK: - Subviews

    private var header: some View {
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
    }

    private var liveBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("We're transcribing this episode now. You can read along as it streams in.")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.secondary)

            ForEach(partial.segments) { seg in
                VStack(alignment: .leading, spacing: 4) {
                    if let speaker = partial.speaker(for: seg.speakerID) {
                        Text(speaker.displayName ?? speaker.label)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(seg.text)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.primary)
                        BlinkingCursor()
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private var skeletonBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ForEach(0..<3, id: \.self) { i in
                SkeletonLine(width: i == 2 ? 0.55 : (i == 1 ? 0.92 : 0.78))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private var cta: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                // No-op for now; Lane 9 will wire notifications.
            } label: {
                Text("Notify me when ready")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, AppTheme.Spacing.md)

            Text("ETA \(etaMinutes) min · ElevenLabs Scribe")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Helpers

private struct BlinkingCursor: View {
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 2, height: 18)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
            .accessibilityHidden(true)
    }
}

private struct SkeletonLine: View {
    let width: CGFloat                    // 0…1 fraction of available width
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.18),
                            Color.secondary.opacity(0.32),
                            Color.secondary.opacity(0.18)
                        ],
                        startPoint: UnitPoint(x: phase - 0.3, y: 0.5),
                        endPoint: UnitPoint(x: phase + 0.3, y: 0.5)
                    )
                )
                .frame(width: geo.size.width * width, height: 18)
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        }
        .frame(height: 18)
    }
}

// MARK: - Preview

#Preview {
    let (episode, transcript) = MockEpisodeFixture.inProgress()
    return NavigationStack {
        TranscribingInProgressView(
            episode: episode,
            partial: transcript,
            progress: 0.38,
            etaMinutes: 4
        )
    }
}
