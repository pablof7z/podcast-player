import AppIntents

/// Registers the app's intents with Siri and the Shortcuts app at build time.
/// Each `AppShortcut` declaration ships a localized invocation phrase so the
/// user can say "Add to {appName}" without manually wiring a shortcut.
///
/// Phrases must contain `\(.applicationName)` so Apple can substitute the
/// localized app name (and apply phrase-grammar variants under the hood).
struct AppTemplateShortcuts: AppShortcutsProvider {

    /// Apple recommends a maximum of 10 shortcuts; we ship three to keep the
    /// Spotlight / Shortcuts surface focused: capture, completion, and status.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add an item to \(.applicationName)",
                "Capture in \(.applicationName)",
            ],
            shortTitle: "Add Item",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: MarkItemDoneIntent(),
            phrases: [
                "Mark done in \(.applicationName)",
                "Complete an item in \(.applicationName)",
            ],
            shortTitle: "Mark Done",
            systemImageName: "checkmark.circle.fill"
        )

        AppShortcut(
            intent: PendingItemCountIntent(),
            phrases: [
                "How many pending in \(.applicationName)",
                "What's pending in \(.applicationName)",
            ],
            shortTitle: "Pending Count",
            systemImageName: "list.bullet"
        )
    }

    /// Tile color in the Shortcuts gallery. Picked to match `AppTheme`'s
    /// accent vibe; override per-product.
    static let shortcutTileColor: ShortcutTileColor = .blue
}
