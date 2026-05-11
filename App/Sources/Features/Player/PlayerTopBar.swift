import SwiftUI

// MARK: - PlayerTopBar
//
// Top bar for the full-screen `PlayerView`. Holds the dismiss button on
// the leading edge, the share / AirPlay / more cluster on the trailing
// edge, and a middle slot that crossfades between the show name and a
// compact artwork+title once the hero header has scrolled offscreen.
//
// All state lives in `PlayerView`; this view is a pure layout container
// driven by the bindings/closures the parent passes in.

struct PlayerTopBar: View {
    @Bindable var state: PlaybackState
    let subscription: PodcastSubscription?
    let showName: String
    let artworkURL: URL?
    let titleCollapsed: Bool

    let onDismiss: () -> Void
    let onShare: () -> Void
    let onShowSleepTimer: () -> Void

    @Environment(AppStateStore.self) private var store

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            jumpBackButton
                .animation(AppTheme.Animation.spring, value: state.canJumpBack)

            Spacer(minLength: AppTheme.Spacing.sm)

            ZStack {
                if titleCollapsed, let episode = state.episode {
                    PlayerCompactTitleView(
                        artworkURL: artworkURL,
                        episodeTitle: episode.title,
                        showName: showName
                    )
                    .transition(.opacity)
                } else if !showName.isEmpty {
                    Text(showName)
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: titleCollapsed)
            .frame(maxWidth: .infinity)

            Spacer(minLength: AppTheme.Spacing.sm)

            HStack(spacing: AppTheme.Spacing.xs) {
                if state.episode != nil {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Share episode")
                }

                routePicker

                if let episode = state.episode {
                    PlayerMoreMenu(
                        episode: episode,
                        subscription: subscription,
                        onMarkPlayed: { store.markEpisodePlayed(episode.id) },
                        onMarkUnplayed: { store.markEpisodeUnplayed(episode.id) },
                        onDismissPlayer: onDismiss,
                        onShowSleepTimer: onShowSleepTimer
                    )
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.xs)
    }

    /// Shows a "< Jump back" text button when there is navigation history,
    /// otherwise renders an empty fixed-size slot so the centre title stays
    /// centred. The drag indicator on the sheet already handles dismiss.
    @ViewBuilder
    private var jumpBackButton: some View {
        if state.canJumpBack {
            Button {
                state.jumpBack()
                Haptics.selection()
            } label: {
                Label("Jump back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Jump back")
            .accessibilityHint("Returns to the previous playback position")
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
        } else {
            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    /// Audio-output route picker styled to match the top-bar glass buttons.
    private var routePicker: some View {
        ZStack {
            Image(systemName: "airplayaudio")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityHidden(true)
            RoutePickerView(activeTintColor: .clear, tintColor: .clear)
                .allowsHitTesting(true)
                .accessibilityHidden(true)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio output")
        .accessibilityHint("Opens system output picker")
    }
}
