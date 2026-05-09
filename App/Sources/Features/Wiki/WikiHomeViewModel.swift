import Foundation
import Observation

// MARK: - Wiki home view model

/// Drives `WikiView` — owns the inventory, the current scope filter,
/// and the page-load actions.
@Observable
@MainActor
final class WikiHomeViewModel {

    // MARK: - State

    var entries: [WikiInventory.Entry] = []
    var scope: ScopeFilter = .global

    /// Storage source. Tests inject a temp-directory storage; the app
    /// uses the default Application Support root.
    var storage: WikiStorage = WikiStorage()

    /// When the storage is empty, we fall back to fixtures so the home
    /// renders something on first launch. Real users in real builds
    /// see this until the agent compiles its first real page.
    var allowFixtureFallback: Bool = true

    // MARK: - Loading

    /// Loads the inventory from disk. On empty + fallback enabled,
    /// substitutes the mock fixture. Filters by `scope` before storing.
    func load() async {
        let inventory: WikiInventory
        if let loaded = try? storage.loadInventory(), !loaded.entries.isEmpty {
            inventory = loaded
        } else if allowFixtureFallback {
            inventory = WikiMockFixture.inventory
        } else {
            inventory = WikiInventory()
        }
        entries = filtered(inventory.entries, by: scope)
    }

    /// Inserts the supplied page into the in-memory inventory and
    /// re-applies the scope filter. The caller is responsible for
    /// persisting via `WikiStorage` separately.
    func add(_ page: WikiPage) {
        let url = storage.pageURL(for: page)
        let entry = WikiInventory.Entry(from: page, fileURL: url)
        entries.removeAll { $0.slug == entry.slug && $0.scope == entry.scope }
        entries.insert(entry, at: 0)
    }

    /// Loads the full page for the supplied entry and hands it to
    /// `present`. Tries disk first, falls back to fixture lookup.
    func openPage(
        _ entry: WikiInventory.Entry,
        present: (WikiPage) -> Void
    ) async {
        if let page = try? storage.read(slug: entry.slug, scope: entry.scope) {
            present(page)
            return
        }
        if let fixture = WikiMockFixture.all
            .first(where: { $0.slug == entry.slug && $0.scope == entry.scope }) {
            present(fixture)
            return
        }
    }

    // MARK: - Scope

    /// The set of scopes present in the loaded inventory, used to drive
    /// the segmented picker.
    var podcastScopes: [ScopeFilter] {
        let podcastScopes: [ScopeFilter] = entries
            .compactMap { entry in
                if case .podcast(let id) = entry.scope {
                    return ScopeFilter.podcast(id)
                }
                return nil
            }
        var seen: Set<ScopeFilter> = []
        return podcastScopes.filter { seen.insert($0).inserted }
    }

    /// Human-readable label for a scope chip. Real builds will resolve
    /// the podcast name via Lane 1's catalog; in stub mode we render
    /// the UUID prefix.
    func label(for scope: ScopeFilter) -> String {
        switch scope {
        case .global: "Library"
        case .podcast(let id):
            "Show \(id.uuidString.prefix(4))"
        }
    }

    private func filtered(
        _ all: [WikiInventory.Entry],
        by scope: ScopeFilter
    ) -> [WikiInventory.Entry] {
        switch scope {
        case .global:
            return all
        case .podcast(let id):
            return all.filter { entry in
                if case .podcast(let entryID) = entry.scope { return entryID == id }
                return false
            }
        }
    }

    // MARK: - Scope filter

    /// Picker-friendly scope variant. Differs from `WikiScope` because the
    /// home wants a "Global = all pages including per-podcast" mode that
    /// the storage scope can't express directly.
    enum ScopeFilter: Hashable {
        case global
        case podcast(UUID)
    }
}
