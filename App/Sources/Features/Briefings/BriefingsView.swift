import SwiftUI

// MARK: - BriefingsView

/// Library shelf for past briefings + Compose entry point. Surface W5
/// (saved-briefing detail) and W1 (compose) of UX-08 are both reached from
/// this view; W2 (player) is a navigation destination.
///
/// The library is tint-segregated from regular podcast episodes per UX-08 §3
/// — a brass-amber `.glassSurface` band wraps every row so a briefing is
/// never mistaken for an episode.
struct BriefingsView: View {

    // MARK: Model

    /// View-model holding the list of saved briefings and the active compose
    /// flow. Owned by the view rather than the global `AppStateStore` so this
    /// lane stays self-contained and other lanes don't have to know about it.
    @State private var model = BriefingsViewModel()

    // MARK: Sheets / nav

    @State private var isComposing = false
    @State private var pendingPlayback: BriefingPlaybackContext?

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                presetRow
                Divider().padding(.horizontal)
                if model.briefings.isEmpty {
                    emptyState
                } else {
                    libraryList
                }
            }
            .padding(.top)
        }
        .background(briefingBackground)
        .navigationTitle("Briefings")
        .toolbar { toolbar }
        .sheet(isPresented: $isComposing) {
            BriefingComposeSheet(
                onCompose: { request in
                    isComposing = false
                    Task { await model.compose(request: request) }
                }
            )
        }
        .navigationDestination(item: $pendingPlayback) { ctx in
            BriefingPlayerView(context: ctx)
        }
        .task { await model.reload() }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { isComposing = true } label: {
                Label("Compose", systemImage: "sparkles")
            }
        }
    }

    // MARK: Preset row

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.md) {
                ForEach(BriefingStyle.allCases, id: \.self) { style in
                    Button {
                        Task {
                            await model.composeQuick(style: style)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: icon(for: style))
                                .font(.title2)
                            Text(style.displayLabel)
                                .font(.headline)
                            Text(blurb(for: style))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(AppTheme.Spacing.md)
                        .frame(width: 180, alignment: .leading)
                    }
                    .glassSurface(
                        cornerRadius: AppTheme.Corner.lg,
                        tint: BriefingsView.brassAmber.opacity(0.18),
                        interactive: true
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func icon(for style: BriefingStyle) -> String {
        switch style {
        case .morning:            "sunrise.fill"
        case .weeklyTLDR:         "calendar.badge.clock"
        case .catchUpOnShow:      "arrow.uturn.backward.circle.fill"
        case .topicAcrossLibrary: "magnifyingglass.circle.fill"
        }
    }

    private func blurb(for style: BriefingStyle) -> String {
        switch style {
        case .morning:            "What matters today, in 8 minutes."
        case .weeklyTLDR:         "The week, condensed."
        case .catchUpOnShow:      "Reconstruct an arc you missed."
        case .topicAcrossLibrary: "Reconcile across shows."
        }
    }

    // MARK: Library list

    private var libraryList: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(model.briefings) { briefing in
                Button {
                    pendingPlayback = BriefingPlaybackContext(script: briefing)
                } label: {
                    BriefingsLibraryRow(script: briefing)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No briefings yet")
                .font(.title3.weight(.semibold))
            Text("Tap a preset above or compose a freeform briefing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }

    // MARK: Background

    private var briefingBackground: some View {
        LinearGradient(
            colors: [
                BriefingsView.brassAmber.opacity(0.08),
                BriefingsView.brassAmber.opacity(0.04),
                Color(.systemBackground),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: Theme

    /// Brass-amber tint defined in UX-08 §4 — *brass-amber glass = the agent
    /// owns this audio*. Kept as a static so the color is consistent across
    /// every briefing surface even if `AppTheme` is later extended.
    static let brassAmber = Color(red: 0.85, green: 0.60, blue: 0.18)
}

// MARK: - Library row

private struct BriefingsLibraryRow: View {
    let script: BriefingScript

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(BriefingsView.brassAmber)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(script.title)
                    .font(.headline)
                Text(script.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(relativeDate(script.generatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(BriefingsView.brassAmber)
        }
        .padding(AppTheme.Spacing.md)
        .glassSurface(
            cornerRadius: AppTheme.Corner.lg,
            tint: BriefingsView.brassAmber.opacity(0.12)
        )
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Playback context (Identifiable for navigationDestination(item:))

struct BriefingPlaybackContext: Identifiable, Hashable {
    let script: BriefingScript
    var id: UUID { script.id }
}
