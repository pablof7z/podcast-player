import SwiftUI

/// Transcript stub.
///
/// The full synced-transcript surface lives in lane-3. Until that lands the
/// player presents a placeholder card so the layout stays stable and the rest
/// of the player chrome can render the real `Episode`-driven playback.
struct PlayerTranscriptScrollView: View {

    @Bindable var state: PlaybackState
    /// Toggles between hero glass card and the bare reading surface used in
    /// transcript-focus layout. Parent supplies whichever framing is live.
    let useGlassCard: Bool

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "text.quote")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text("Transcripts coming soon")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(.white.opacity(0.85))
            Text("Synced, searchable transcripts arrive in a follow-up release.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.lg)
        .background(transcriptBackground)
    }

    @ViewBuilder
    private var transcriptBackground: some View {
        if useGlassCard {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            Color.clear
        }
    }
}
