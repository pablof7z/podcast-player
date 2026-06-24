// MARK: - PlayerTab

/// Discriminated union for the three swipeable panels in the full-screen player.
///
/// `.chapters` (default) — the chapter rail interleaved with episode notes.
/// `.transcript` — the playback-synced transcript with long-press context menu.
/// `.showNotes` — the HTML/plain-text publisher description.
enum PlayerTab: Int, CaseIterable, Identifiable, Hashable {
    case chapters
    case transcript
    case showNotes

    var id: Int { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .chapters:   return "Chapters"
        case .transcript: return "Transcript"
        case .showNotes:  return "Show Notes"
        }
    }
}
