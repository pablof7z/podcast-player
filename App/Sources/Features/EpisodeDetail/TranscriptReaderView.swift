import SwiftUI

// MARK: - TranscriptReaderView

/// Full transcript reader per UX-03 §3-§5:
///   - Editorial serif body (New York via `.serif` design); SF Rounded for
///     speaker labels; SF Mono for timestamps.
///   - Paragraph grouping by speaker switch.
///   - Tap a line → `onJump(to:)` to scrub the player.
///   - Long-press a line → `onShare(segment:)` to open the quote share sheet.
///   - When `currentTime` is non-nil and `followAlong` is on, the active
///     segment is tinted and auto-scrolls into the upper third of the column.
///
/// File-size note: kept on this side of the soft 300-line limit by extracting
/// the row into `TranscriptRow` and the speaker chip into `SpeakerChip`.
struct TranscriptReaderView: View {

    // MARK: Inputs

    let episode: Episode
    let transcript: Transcript
    let currentTime: TimeInterval?
    let followAlong: Bool
    let onJump: (TimeInterval) -> Void
    let onShare: (Segment) -> Void

    // MARK: State

    @State private var activeSegmentID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    paragraphs
                        .frame(maxWidth: 640, alignment: .leading)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemBackground))
            .onChange(of: currentTime) { _, newValue in
                guard followAlong, let now = newValue else { return }
                if let active = transcript.segment(at: now), active.id != activeSegmentID {
                    activeSegmentID = active.id
                    withAnimation(.easeOut(duration: 0.4)) {
                        proxy.scrollTo(active.id, anchor: .top)
                    }
                }
            }
            .accessibilityRotor("Paragraphs") {
                ForEach(transcript.segments) { seg in
                    AccessibilityRotorEntry(rotorLabel(for: seg), id: seg.id)
                }
            }
        }
    }

    // MARK: - Subviews

    private var paragraphs: some View {
        let groups = paragraphGroups(transcript.segments)
        return ForEach(groups, id: \.id) { group in
            VStack(alignment: .leading, spacing: 6) {
                if let speaker = transcript.speaker(for: group.speakerID) {
                    SpeakerChip(name: speaker.displayName ?? speaker.label,
                                timestamp: format(group.start))
                }
                ForEach(group.segments) { seg in
                    TranscriptRow(
                        segment: seg,
                        isActive: seg.id == activeSegmentID,
                        onTap: { onJump(seg.start) },
                        onLongPress: { onShare(seg) }
                    )
                    .id(seg.id)
                    .holdToClip(episode: episode, transcript: transcript, segment: seg)
                }
            }
        }
    }

    // MARK: - Grouping

    private struct ParagraphGroup: Identifiable {
        let id = UUID()
        let speakerID: UUID?
        let start: TimeInterval
        var segments: [Segment]
    }

    private func paragraphGroups(_ segments: [Segment]) -> [ParagraphGroup] {
        var groups: [ParagraphGroup] = []
        for seg in segments {
            if var last = groups.last, last.speakerID == seg.speakerID {
                last.segments.append(seg)
                groups[groups.count - 1] = last
            } else {
                groups.append(ParagraphGroup(speakerID: seg.speakerID, start: seg.start, segments: [seg]))
            }
        }
        return groups
    }

    private func rotorLabel(for seg: Segment) -> String {
        let name = transcript.speaker(for: seg.speakerID)?.displayName ?? "Speaker"
        return "\(name), \(format(seg.start)), paragraph"
    }

    private func format(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - SpeakerChip

private struct SpeakerChip: View {
    let name: String
    let timestamp: String

    var body: some View {
        HStack(spacing: 8) {
            Text(name.uppercased())
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.primary)
            Text(timestamp)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 8)
    }
}

// MARK: - TranscriptRow

private struct TranscriptRow: View {
    let segment: Segment
    let isActive: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Text(segment.text)
            .font(AppTheme.Typography.body)
            .lineSpacing(11)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.yellow.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.3) { onLongPress() }
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#Preview {
    let subID = UUID()
    let episode = Episode(
        subscriptionID: subID,
        guid: "preview-1",
        title: "How to Think About Keto",
        description: "",
        pubDate: Date(timeIntervalSince1970: 1_714_780_800),
        duration: 60 * 60 * 2,
        enclosureURL: URL(string: "https://traffic.megaphone.fm/HSW1234567890.mp3")!
    )
    let tim = Speaker(label: "Tim Ferriss", displayName: "Tim Ferriss")
    let peter = Speaker(label: "Peter Attia", displayName: "Peter Attia")
    let transcript = Transcript(
        episodeID: episode.id,
        language: "en-US",
        source: .publisher,
        segments: [
            Segment(start: 0, end: 6, speakerID: tim.id, text: "Welcome back to the show. Today I'm joined by my friend Dr. Peter Attia."),
            Segment(start: 6, end: 10, speakerID: peter.id, text: "Thanks Tim, great to be here."),
            Segment(start: 252, end: 260, speakerID: tim.id, text: "When you say metabolic flexibility, what do you actually mean?"),
            Segment(start: 260, end: 270, speakerID: peter.id, text: "We're measuring the body's ability to switch substrate utilization on demand.")
        ],
        speakers: [tim, peter]
    )
    return TranscriptReaderView(
        episode: episode,
        transcript: transcript,
        currentTime: 260,
        followAlong: true,
        onJump: { _ in },
        onShare: { _ in }
    )
}
