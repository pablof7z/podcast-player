import SwiftUI

// MARK: - Search result types

enum SearchResult: Identifiable, Hashable {
    case note(Note)
    case memory(AgentMemory)

    var id: String {
        switch self {
        case .note(let n):   "note-\(n.id)"
        case .memory(let m): "memory-\(m.id)"
        }
    }
}

// MARK: - Sectioned results list

/// Renders two labelled sections (Notes, Memories) for a given query.
/// Empty sections are hidden. Tapping a result fires `onSelect`.
struct UniversalSearchResults: View {
    let query: String
    let noteResults: [Note]
    let memoryResults: [AgentMemory]
    var onSelect: (SearchResult) -> Void

    var body: some View {
        if noteResults.isEmpty && memoryResults.isEmpty {
            noResults
        } else {
            sections
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        if !noteResults.isEmpty {
            Section("Notes") {
                ForEach(noteResults) { note in
                    SearchNoteRow(note: note, query: query)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(.note(note)) }
                }
            }
        }

        if !memoryResults.isEmpty {
            Section("Memories") {
                ForEach(memoryResults) { memory in
                    SearchMemoryRow(memory: memory, query: query)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(.memory(memory)) }
                }
            }
        }
    }

    // MARK: - Empty

    private var noResults: some View {
        ContentUnavailableView.search(text: query)
            .listRowBackground(Color.clear)
    }

    // MARK: - Row types

    private enum Layout {
        static let iconFrame: CGFloat = 22
    }

    private struct SearchNoteRow: View {
        let note: Note
        let query: String

        var body: some View {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: noteIcon)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(noteColor)
                    .frame(width: Layout.iconFrame, height: Layout.iconFrame)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HighlightedText(text: note.text, query: query)
                        .font(AppTheme.Typography.callout)
                        .lineLimit(3)

                    HStack(spacing: AppTheme.Spacing.xs) {
                        if note.kind == .reflection {
                            Text("reflection")
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, AppTheme.Spacing.xs)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.10), in: Capsule())
                        }
                        Text(RelativeTimestamp.extended(note.createdAt))
                            .font(AppTheme.Typography.mono)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }

        private var noteIcon: String {
            note.kind == .reflection ? "sparkles" : "note.text"
        }

        private var noteColor: Color {
            note.kind == .reflection ? .orange : .indigo
        }
    }

    private struct SearchMemoryRow: View {
        let memory: AgentMemory
        let query: String

        var body: some View {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "brain")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.purple)
                    .frame(width: Layout.iconFrame, height: Layout.iconFrame)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HighlightedText(text: memory.content, query: query)
                        .font(AppTheme.Typography.callout)
                        .lineLimit(3)

                    Text(RelativeTimestamp.extended(memory.createdAt))
                        .font(AppTheme.Typography.mono)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }
}

// MARK: - Highlighted text

/// Renders `text` with each case-insensitive occurrence of `query` bolded.
struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var out = AttributedString(text)
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return out }

        let lText = text.lowercased()
        let lQuery = trimmed.lowercased()
        var start = lText.startIndex
        while let range = lText.range(of: lQuery, range: start..<lText.endIndex) {
            let lo = lText.distance(from: lText.startIndex, to: range.lowerBound)
            let hi = lText.distance(from: lText.startIndex, to: range.upperBound)
            if let s = Self.attributedIndex(out, out.startIndex, offsetBy: lo),
               let e = Self.attributedIndex(out, out.startIndex, offsetBy: hi) {
                out[s..<e].font = .body.bold()
                out[s..<e].foregroundColor = .accentColor
            }
            start = range.upperBound
        }
        return out
    }

    private static func attributedIndex(
        _ string: AttributedString,
        _ base: AttributedString.Index,
        offsetBy n: Int
    ) -> AttributedString.Index? {
        var idx = base
        for _ in 0..<n {
            guard idx < string.endIndex else { return nil }
            idx = string.characters.index(after: idx)
        }
        return idx
    }
}
