import AppIntents
import Foundation
import os.log

// MARK: - FocusFilterStore

/// Lightweight App Group store for the Focus-mode filter setting.
///
/// Written by `FocusFilterIntent` when the system activates a configured Focus
/// and read by `HomeView` on every `scenePhase` transition to `.active`.
///
/// Uses the same App Group suite as `Persistence` so the key is visible to both
/// the app process and extensions (Siri, Widgets) without any extra setup.
enum FocusFilterStore {

    /// The tag string to filter by when a Focus is active; `nil` when Focus is
    /// inactive or the user selected "Priority" or "All" as their focus filter.
    static let focusTagKey     = "apptemplate.focus.tag"
    /// Stores "priority" or "all" for non-tag choices.
    static let focusChoiceKey  = "apptemplate.focus.choice"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: Persistence.appGroupIdentifier) ?? .standard
    }

    /// Writes the active focus filter so the app can read it on resume.
    static func save(choice: FocusChoice) {
        switch choice {
        case .all:
            defaults.removeObject(forKey: focusTagKey)
            defaults.set("all", forKey: focusChoiceKey)
        case .priority:
            defaults.removeObject(forKey: focusTagKey)
            defaults.set("priority", forKey: focusChoiceKey)
        case .tag(let t):
            defaults.set(t, forKey: focusTagKey)
            defaults.set("tag", forKey: focusChoiceKey)
        }
    }

    /// Clears any stored focus filter (called when Focus is deactivated).
    static func clear() {
        defaults.removeObject(forKey: focusTagKey)
        defaults.removeObject(forKey: focusChoiceKey)
    }

    /// Reads the stored focus filter, or `nil` if none is active.
    static func load() -> FocusChoice? {
        guard let raw = defaults.string(forKey: focusChoiceKey) else { return nil }
        switch raw {
        case "all":      return .all
        case "priority": return .priority
        case "tag":
            guard let tag = defaults.string(forKey: focusTagKey), !tag.isEmpty else { return nil }
            return .tag(tag)
        default:         return nil
        }
    }
}

// MARK: - FocusChoice

/// The filter mode the user selects for a Focus configuration.
enum FocusChoice: Equatable, Sendable {
    case all
    case priority
    case tag(String)
}

// MARK: - FocusFilterStyle (AppEntity for picker)

/// An entity representing one of the built-in Focus filter styles.
/// Drives the style picker in `FocusFilterIntent` via `DynamicOptionsProvider`.
struct FocusFilterStyle: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Focus Filter Style"
    static let defaultQuery = FocusFilterStyleQuery()

    var id: String
    var title: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    // Built-in styles exposed as constants.
    static let all      = FocusFilterStyle(id: "all",      title: "All Items",    subtitle: "Show everything — no filter applied")
    static let priority = FocusFilterStyle(id: "priority", title: "Priority Only", subtitle: "Show only starred items")
}

struct FocusFilterStyleQuery: EntityQuery, EnumerableEntityQuery, Sendable {
    func entities(for identifiers: [String]) async throws -> [FocusFilterStyle] {
        let all: [FocusFilterStyle] = [.all, .priority]
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FocusFilterStyle] {
        [.all, .priority]
    }

    func allEntities() async throws -> [FocusFilterStyle] {
        [.all, .priority]
    }
}

// MARK: - FocusFilterIntent

/// Integrates with iOS Focus modes (System → Focus → App Filter).
///
/// When a user creates a Focus (Work, Personal, etc.) and attaches this filter,
/// the system calls `perform()` whenever that Focus becomes active, and
/// `removedFromFocus()` when it ends. The chosen style is written to the
/// shared App Group UserDefaults; `HomeView` reads it on scene activation.
///
/// **What the user sees:**
///   - "Focus Filter Style" picker: All Items, Priority Only
///   - Optional "Tag" field: free-text tag name (overrides the style picker)
///
/// **Tag takes precedence over style.** If the user types a tag name, the list
/// filters to that tag regardless of the style picker selection.
struct FocusFilterIntent: SetFocusFilterIntent {
    private static let logger = Logger.app("FocusFilterIntent")
    static let title: LocalizedStringResource = "App Template Focus Filter"
    static let description = IntentDescription(
        "Filters your item list while a Focus is active. Choose a built-in style or enter a tag name to show only matching items.",
        categoryName: "Focus"
    )

    // MARK: - Parameters

    @Parameter(
        title: "Style",
        description: "Which items to show while this Focus is active. Ignored when a Tag is entered.",
        default: .all
    )
    var style: FocusFilterStyle

    @Parameter(
        title: "Tag",
        description: "Optional tag name (without #). When set, only items with this tag are shown during the Focus."
    )
    var tag: String?

    // MARK: - SetFocusFilterIntent

    var displayRepresentation: DisplayRepresentation {
        if let tag = tag?.trimmed, !tag.isEmpty {
            return DisplayRepresentation(
                title: "Filter by #\(tag)",
                subtitle: "Active during this Focus"
            )
        }
        switch style.id {
        case "priority":
            return DisplayRepresentation(
                title: "Priority Only",
                subtitle: "Active during this Focus"
            )
        default:
            return DisplayRepresentation(
                title: "All Items",
                subtitle: "Active during this Focus"
            )
        }
    }

    func perform() async throws -> some IntentResult {
        let choice = resolvedChoice()
        Self.logger.info("FocusFilterIntent: activating — \(debugDescription(choice), privacy: .public)")
        // When the resolved choice is `.all` (the default / "no filter") treat it
        // as a deactivation signal and clear the store entirely. This ensures the
        // Focus chip disappears from HomeView when the system calls perform() with
        // default parameters to indicate that the Focus has been deactivated.
        if case .all = choice {
            FocusFilterStore.clear()
        } else {
            FocusFilterStore.save(choice: choice)
        }
        return .result()
    }

    // MARK: - Private helpers

    /// Resolves the effective filter choice from the current parameter values.
    /// Tag wins over style when non-empty.
    private func resolvedChoice() -> FocusChoice {
        if let raw = tag?.trimmed, !raw.isEmpty { return .tag(raw) }
        switch style.id {
        case "priority": return .priority
        default:         return .all
        }
    }

    private func debugDescription(_ choice: FocusChoice) -> String {
        switch choice {
        case .all:         return "all"
        case .priority:    return "priority"
        case .tag(let t):  return "tag:\(t)"
        }
    }
}

