import SwiftUI

/// Full-screen Now Playing surface.
///
/// Layered top-down: hero artwork placeholder → editorial metadata →
/// transcript stub → semantic waveform → primary transport → action cluster.
/// All colors and fonts use semantic / Dynamic Type styles so the surface
/// adapts to the user's appearance settings and accent color.
struct PlayerView: View {

    @Environment(AppStateStore.self) private var store
    @Bindable var state: PlaybackState
    @Environment(\.dismiss) private var dismiss
    let glassNamespace: Namespace.ID

    @State private var isScrubbing: Bool = false
    @State private var showSpeedSheet: Bool = false
    @State private var showSleepSheet: Bool = false
    @State private var showQueueSheet: Bool = false
    @State private var showShareSheet: Bool = false

    private var subscription: PodcastSubscription? {
        guard let subID = state.episode?.subscriptionID else { return nil }
        return store.subscription(id: subID)
    }

    private var showName: String {
        subscription?.title ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    heroArtwork
                    editorialHeader
                    PlayerTranscriptScrollView(state: state, useGlassCard: true)
                        .frame(minHeight: 240, maxHeight: 320)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            }

            playbackChrome
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.md)
        }
        .sheet(isPresented: $showSpeedSheet) { PlayerSpeedSheet(state: state) }
        .sheet(isPresented: $showSleepSheet) { PlayerSleepTimerSheet(state: state) }
        .sheet(isPresented: $showQueueSheet) {
            PlayerQueueSheet(state: state)
        }
        .sheet(isPresented: $showShareSheet) {
            if let episode = state.episode {
                PlayerShareSheet(state: state, episode: episode, showName: showName)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Minimize player")

            Spacer()

            Text("NOW PLAYING")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            Spacer()

            if let episode = state.episode {
                PlayerMoreMenu(
                    episode: episode,
                    subscription: subscription,
                    onMarkPlayed: { store.markEpisodePlayed(episode.id) },
                    onMarkUnplayed: { store.markEpisodeUnplayed(episode.id) },
                    onDismissPlayer: { dismiss() }
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Hero artwork

    /// Episode cover art preferring per-episode `imageURL` (some shows ship
    /// per-episode artwork) and falling back to the subscription's show
    /// artwork. Both are populated by the RSS parser; falls back to a calm
    /// placeholder while the image loads or if neither URL is available.
    private var artworkURL: URL? {
        state.episode?.imageURL ?? subscription?.imageURL
    }

    private var heroArtwork: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        Image(systemName: "waveform")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.secondary)
                    @unknown default:
                        Image(systemName: "waveform")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isScrubbing ? 180 : 260)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.xl, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .scaleEffect(isScrubbing ? 1.04 : 1.0)
        .blur(radius: isScrubbing ? 8 : 0)
        .glassEffectID("player.artwork", in: glassNamespace)
        .animation(AppTheme.Animation.spring, value: isScrubbing)
        .accessibilityHidden(true)
    }

    // MARK: - Editorial header

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let episode = state.episode {
                if !showName.isEmpty {
                    Text(showName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                }
                Text(episode.title)
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Playback chrome (waveform + transport + actions)

    private var playbackChrome: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            PlayerScrubberView(state: state, isScrubbing: $isScrubbing)
            PlayerControlsView(
                state: state,
                glassNamespace: glassNamespace
            )
            PlayerActionClusterView(
                state: state,
                showSpeedSheet: $showSpeedSheet,
                showSleepSheet: $showSleepSheet,
                showQueueSheet: $showQueueSheet,
                showShareSheet: $showShareSheet
            )
        }
    }
}
