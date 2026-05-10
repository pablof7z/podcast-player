import SwiftUI

// MARK: - Citation chip

/// Small glass capsule rendering a single `WikiCitation`'s timestamp.
///
/// Two gestures:
///   - **Tap** dispatches `play_episode_at` via `PlaybackState` (set the
///     episode, seek to `startMS`, play).
///   - **Long-press** presents a `CitationPeekSheet` so the user can audition
///     the cited 12 seconds without losing their place.
///
/// Visually mirrors UX-04's amber chip palette but renders with the Liquid
/// Glass material so it morphs alongside the rest of the floating wiki
/// chrome.
struct CitationChip: View {

    let citation: WikiCitation
    /// Episode resolver — the chip needs an `Episode` instance to hand off
    /// to the player, but doesn't want to depend on the store's concrete
    /// type. The host view injects `store.episode(id:)`.
    let resolveEpisode: (UUID) -> Episode?

    @Environment(PlaybackState.self) private var playback
    @State private var peeking = false

    var body: some View {
        Button {
            playClipImmediate()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.caption2)
                Text(citation.formattedTimestamp)
                    .font(.system(.caption, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: .capsule)
            )
            .overlay(
                Capsule()
                    .strokeBorder(CitationChip.amber.opacity(0.35), lineWidth: 0.5)
            )
            .foregroundStyle(CitationChip.amber)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    Haptics.selection()
                    peeking = true
                }
        )
        .sheet(isPresented: $peeking) {
            CitationPeekSheet(
                citation: citation,
                resolveEpisode: resolveEpisode
            )
            .presentationDetents([.fraction(0.42), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
        .accessibilityLabel("Citation at \(citation.formattedTimestamp), tap to play, hold to peek")
    }

    // MARK: - Actions

    /// Fires the wiki-citation deep-link contract: jump the player straight
    /// to the cited timestamp and start playback. Falls back to a
    /// `NotificationCenter` post when the episode can't be resolved locally
    /// — preserves backward compatibility with the original peek view's
    /// stub contract.
    private func playClipImmediate() {
        Haptics.selection()
        if let episode = resolveEpisode(citation.episodeID) {
            playback.setEpisode(episode)
            playback.seek(to: TimeInterval(citation.startMS) / 1_000)
            playback.play()
            return
        }
        NotificationCenter.default.post(
            name: CitationPeekView.playClipNotification,
            object: nil,
            userInfo: [
                "episodeID": citation.episodeID.uuidString,
                "startMS": citation.startMS,
                "endMS": citation.endMS,
            ]
        )
    }

    // MARK: - Palette

    static let amber = Color(red: 0.72, green: 0.45, blue: 0.10)
}
