import SwiftUI

// MARK: - PlayerTranscriptRow

/// Single transcript line inside the full-screen player's Transcript tab.
///
/// Visual priorities:
///   - Active line gets a gentle accent-color underlay so it stands out on any
///     player backdrop (light or dark).
///   - Speaker label sits inline as a small uppercase chip above the line, so
///     consecutive same-speaker rows stay visually packed.
///   - Long-press exposes optional actions for asking the agent, creating a
///     clip, and highlighting the line without forcing preview callers to wire
///     stub closures.
struct PlayerTranscriptRow: View {

    let segment: Segment
    let speaker: Speaker?
    let isActive: Bool
    let onTap: () -> Void
    /// Long-press → "Ask the agent about this moment".
    var onAskAgent: (() -> Void)? = nil
    /// Long-press → "Create Clip" — opens `ClipComposerSheet` pre-populated
    /// with this segment's time boundaries. Optional; defaults to nil.
    var onCreateClip: (() -> Void)? = nil
    /// Long-press → "Highlight" — copies the text to the clipboard and posts a
    /// haptic. A future slice will wire this to a persistent highlight store.
    var onHighlight: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let speakerName {
                Text(speakerName.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }
            Text(segment.text)
                .font(.system(.body))
                .lineSpacing(6)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(activeBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu { contextMenuContent }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Ask the agent")) { onAskAgent?() }
        .accessibilityAction(named: Text("Create Clip")) { onCreateClip?() }
        .accessibilityAction(named: Text("Highlight")) { onHighlight?() }
    }

    // MARK: - Private helpers

    private var activeBackground: some View {
        // Active row uses the system accent at low opacity — the whole player
        // no longer assumes dark chrome, so hardcoded white broke in light mode.
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.20) : Color.clear, lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let onAskAgent {
            Button {
                Haptics.selection()
                onAskAgent()
            } label: {
                Label("Ask the agent about this", systemImage: "sparkles")
            }
        }
        if let onCreateClip {
            Button {
                Haptics.selection()
                onCreateClip()
            } label: {
                Label("Create Clip", systemImage: "film.stack")
            }
        }
        if let onHighlight {
            Button {
                Haptics.selection()
                onHighlight()
            } label: {
                Label("Highlight", systemImage: "highlighter")
            }
        }
    }

    private var speakerName: String? {
        guard let speaker else { return nil }
        return speaker.displayName ?? speaker.label
    }

    private var accessibilityText: String {
        if let speakerName { return "\(speakerName), \(segment.text)" }
        return segment.text
    }
}
