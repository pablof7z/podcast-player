import SwiftUI
import UIKit

// MARK: - PlayerMoreMenu

/// Top-bar "More" pull-down for the full-screen `PlayerView`.
///
/// Apple's standard `Menu` ergonomics fit better here than a sheet — short
/// list, one tap to dispatch, no transient state between selections. Render
/// is wrapped in a glass capsule so it matches the surrounding chrome.
///
/// Navigation items (Go to episode / Go to show) dismiss the player and
/// dispatch a `podcastr://` deep-link. `RootView.onOpenURL` already routes
/// these into the correct detail sheet, so no additional plumbing is needed
/// from this surface.
struct PlayerMoreMenu: View {

    let episode: Episode
    let subscription: PodcastSubscription?
    let onMarkPlayed: () -> Void
    let onMarkUnplayed: () -> Void
    let onDismissPlayer: () -> Void
    let onShowSleepTimer: () -> Void

    /// Drives the brief "Copied!" label swap on the Copy item. Resets after
    /// `Self.copyAckDuration` so the next pull-down shows the canonical label.
    /// Menu items can't host transient toasts, so the label flip is the most
    /// honest in-line acknowledgement we can give.
    @State private var didCopyLink: Bool = false

    /// How long the "Copied!" affordance stays visible after a copy.
    private static let copyAckDuration: Duration = .milliseconds(1_400)

    var body: some View {
        Menu {
            Button {
                Haptics.selection()
                onShowSleepTimer()
            } label: {
                Label("Sleep Timer", systemImage: "moon.fill")
            }

            Divider()

            Button {
                Haptics.selection()
                if episode.played {
                    onMarkUnplayed()
                } else {
                    onMarkPlayed()
                }
            } label: {
                // Filled glyph reads as "this state is currently true" —
                // matches Apple's Mail/Reminders pattern for a toggled checkmark.
                Label(
                    episode.played ? "Mark as unplayed" : "Mark as played",
                    systemImage: episode.played ? "circle" : "checkmark.circle.fill"
                )
            }

            Button {
                Haptics.selection()
                openEpisode()
            } label: {
                Label("Go to episode", systemImage: "doc.text")
            }

            if let subscription {
                Button {
                    Haptics.selection()
                    openShow(subscription)
                } label: {
                    Label("Go to show", systemImage: "rectangle.stack")
                }
            }

            Divider()

            Button {
                Haptics.success()
                UIPasteboard.general.string = episodeDeepLink
                acknowledgeCopy()
            } label: {
                Label(
                    didCopyLink ? "Copied!" : "Copy episode link",
                    systemImage: didCopyLink ? "checkmark" : "link"
                )
            }

            if let feedURL = subscription?.feedURL {
                Button {
                    Haptics.light()
                    UIApplication.shared.open(feedURL)
                } label: {
                    Label("Open RSS feed", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("More options")
    }

    // MARK: - Deep-link helpers

    /// `podcastr://e/<guid>` — the lane-spec literal format. Different from
    /// the in-app `podcastr://episode/<uuid>` route the deep-link handler
    /// recognises today, but matches what the spec asks the share/copy paths
    /// to surface for forward compat with publisher-side link unfurling.
    private var episodeDeepLink: String {
        DeepLinkHandler.episodeGUIDDeepLink(guid: episode.guid)
            ?? episode.enclosureURL.absoluteString
    }

    /// Dismiss the player, then route via the existing `podcastr://episode/<uuid>`
    /// deep-link (handled by `RootView.handleDeepLink`). Order matters:
    /// `UIApplication.open` is queued onto the next runloop so the dismiss
    /// animation has time to finish before the spotlight sheet presents,
    /// otherwise the cover swallows the URL.
    private func openEpisode() {
        guard let url = URL(string: "podcastr://episode/\(episode.id.uuidString)") else { return }
        onDismissPlayer()
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    private func openShow(_ subscription: PodcastSubscription) {
        guard let url = URL(string: "podcastr://subscription/\(subscription.id.uuidString)") else { return }
        onDismissPlayer()
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    /// Flip the Copy item's label/icon to the success affordance, then auto-reset
    /// so the menu reads canonically the next time it's pulled down. Detached
    /// task because the menu often dismisses on selection — we still want the
    /// reset to fire so a *re-open* before the timer expires doesn't see a
    /// stuck "Copied!" label.
    private func acknowledgeCopy() {
        didCopyLink = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.copyAckDuration)
            didCopyLink = false
        }
    }
}
