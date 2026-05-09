import SwiftUI
import UIKit

// MARK: - PlayerShareSheet

/// Share sheet presented from the player's Share chip.
///
/// Targets, in order:
///   - **Copy episode link** — `podcastr://e/<guid>` deep link.
///   - **Copy link with timestamp** — same, with `?t=<seconds>` appended so
///     a recipient lands at the current playhead.
///   - **Share via system** — SwiftUI `ShareLink` over the deep link.
///   - **Share quote** — presents `QuoteShareView` for the segment at the
///     current time. Gated on `episode.transcriptState == .ready` (which
///     means hidden in this lane until lane 5 / transcript ingestion lands —
///     `PlayerTranscriptScrollView` is also a placeholder in this build).
struct PlayerShareSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var state: PlaybackState
    let episode: Episode
    let showName: String

    /// Threshold below which a "share at current time" link would be
    /// indistinguishable from a fresh-start share. Picked at 5s so a brief
    /// pre-roll skim doesn't spuriously enable the row.
    private static let timestampedShareMinSeconds: TimeInterval = 5

    /// Resolved transcript segment at the current playhead, surfaced via the
    /// quote-share sheet. Set when the user taps "Share quote"; reset when the
    /// sheet dismisses. Optional `Segment` is `Identifiable`, which `sheet(item:)`
    /// requires.
    @State private var quotingSegment: Segment?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.md) {
                copyLinkButton
                if hasMeaningfulPlayhead {
                    copyTimestampedLinkButton
                }
                systemShareButton
                if hasReadyTranscript {
                    shareQuoteButton
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $quotingSegment) { segment in
                quoteSheet(for: segment)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Targets

    private var copyLinkButton: some View {
        shareRow(label: "Copy episode link", systemImage: "link") {
            Haptics.light()
            UIPasteboard.general.string = episodeDeepLink
        }
    }

    private var copyTimestampedLinkButton: some View {
        shareRow(label: "Copy link at current time", systemImage: "clock") {
            Haptics.light()
            UIPasteboard.general.string = timestampedDeepLink
        }
    }

    @ViewBuilder
    private var systemShareButton: some View {
        if let url = URL(string: episodeDeepLink) {
            ShareLink(item: url, subject: Text(episode.title)) {
                shareRowLabel(label: "Share via…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
    }

    private var shareQuoteButton: some View {
        shareRow(label: "Share quote", systemImage: "text.quote") {
            presentQuoteAtPlayhead()
        }
    }

    /// Load the persisted transcript for this episode, find the segment at the
    /// current playhead, and present `QuoteShareView` for it. We resolve via
    /// `EpisodeDetailView.readyTranscript(for:)` to share the same defensive
    /// "state says ready but file is missing" handling — no point reimplementing
    /// the gate in two places.
    private func presentQuoteAtPlayhead() {
        guard let transcript = EpisodeDetailView.readyTranscript(for: episode),
              let segment = transcript.segment(at: state.currentTime) else {
            // Soft-fail: the gate above keeps us out of here when transcripts
            // aren't ready, but file-missing or pre-first-segment scrub is
            // still possible. A muted error haptic is the most honest signal —
            // a thrown alert would be disproportionate for a share affordance.
            Haptics.error()
            return
        }
        Haptics.light()
        quotingSegment = segment
    }

    @ViewBuilder
    private func quoteSheet(for segment: Segment) -> some View {
        let transcript = EpisodeDetailView.readyTranscript(for: episode)
        QuoteShareView(
            episode: episode,
            showName: showName,
            showImageURL: episode.imageURL,
            segment: segment,
            speaker: transcript?.speaker(for: segment.speakerID),
            deepLink: quoteDeepLink(for: segment)
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// Mirror of `EpisodeDetailView.deepLink(for:segment:)` — the prefix is the
    /// first alphanumeric run of the episode GUID so the link stays stable
    /// across pretty-print serializers without leaking publisher slashes.
    private func quoteDeepLink(for segment: Segment) -> String {
        let prefix = episode.guid
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .first
            .map(String.init) ?? "ep"
        return "podcastr://e/\(prefix)?t=\(Int(segment.start))"
    }

    // MARK: - Row plumbing

    private func shareRow(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            shareRowLabel(label: label, systemImage: systemImage)
        }
        .buttonStyle(.pressable)
    }

    private func shareRowLabel(label: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 22, alignment: .center)
            Text(label)
                .font(AppTheme.Typography.subheadline)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(label)
    }

    // MARK: - Deep-link helpers

    /// Spec literal: `podcastr://e/<guid>`. Distinct from the in-app
    /// `podcastr://episode/<uuid>` route the deep-link handler currently
    /// recognises — kept this way for forward compat with publisher-side
    /// link unfurling once a `e/` route lands.
    private var episodeDeepLink: String {
        "podcastr://e/\(episode.guid)"
    }

    private var timestampedDeepLink: String {
        let seconds = max(0, Int(state.currentTime))
        return "\(episodeDeepLink)?t=\(seconds)"
    }

    private var hasReadyTranscript: Bool {
        if case .ready = episode.transcriptState { return true }
        return false
    }

    /// True when the playhead is far enough into the episode that a "share at
    /// current time" link carries meaningful information beyond a fresh-start
    /// share. Pulled out as a helper (with an internal-visible static twin
    /// below) so the predicate can be unit-tested without standing up a
    /// SwiftUI view hierarchy.
    var hasMeaningfulPlayhead: Bool {
        Self.isMeaningfulPlayhead(state.currentTime)
    }

    /// Pure predicate for the timestamp-share gate. Exposed for tests.
    static func isMeaningfulPlayhead(_ currentTime: TimeInterval) -> Bool {
        currentTime > timestampedShareMinSeconds
    }
}
