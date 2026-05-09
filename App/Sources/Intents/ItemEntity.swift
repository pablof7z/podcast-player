import AppIntents
import Foundation
import os.log

/// Surfaces `Item` to AppIntents. Conforming `Item` itself would force its
/// pure `Sendable` value type to import `AppIntents`; instead we wrap it in a
/// thin entity that points back to the underlying record by `UUID`.
///
/// `IndexedEntity` lets the Shortcuts app and Spotlight learn which items
/// exist without the app being open — paired with `ItemEntityQuery`'s
/// `suggestedEntities`, the system can present a picker for "Mark Item Done".
struct ItemEntity: AppEntity, IndexedEntity, Sendable {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Item"
    static let defaultQuery = ItemEntityQuery()

    var id: UUID
    var title: String
    var status: ItemStatus

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: status == .done ? "Done" : (status == .dropped ? "Dropped" : "Pending")
        )
    }

    init(from item: Item) {
        self.id = item.id
        self.title = item.title
        self.status = item.status
    }
}

/// Loads `ItemEntity` instances from persisted state. All access goes through
/// `Persistence.load()` so this works inside the Siri / Shortcuts extension
/// host where `AppStateStore` is unreachable.
struct ItemEntityQuery: EntityQuery, Sendable {
    private static let logger = Logger.app("ItemEntityQuery")

    /// Read-only loader for query callbacks. Decode errors are logged to stderr
    /// and surface as an empty `AppState` so the picker silently degrades to "no
    /// items" instead of crashing the Shortcuts host. Mutating intents must use
    /// `try Persistence.load()` directly so they can refuse to overwrite data
    /// they failed to read.
    fileprivate static func loadStateLogged() -> AppState {
        do {
            return try Persistence.load()
        } catch {
            Self.logger.error("ItemEntityQuery: load failed: \(error, privacy: .public)")
            return AppState()
        }
    }

    func entities(for identifiers: [ItemEntity.ID]) async throws -> [ItemEntity] {
        let state = Self.loadStateLogged()
        let lookup = Dictionary(uniqueKeysWithValues: state.items.map { ($0.id, $0) })
        return identifiers.compactMap { id in
            guard let item = lookup[id], !item.deleted else { return nil }
            return ItemEntity(from: item)
        }
    }

    /// What the Shortcuts picker shows by default — pending items only,
    /// freshest first, capped so we don't dump a 1000-item list into Siri.
    func suggestedEntities() async throws -> [ItemEntity] {
        let state = Self.loadStateLogged()
        return state.items
            .filter { !$0.deleted && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(50)
            .map(ItemEntity.init(from:))
    }
}

extension ItemEntityQuery: EnumerableEntityQuery {
    /// Required by `IndexedEntity` so the system can learn the full set of
    /// items for predictions / Spotlight donations.
    func allEntities() async throws -> [ItemEntity] {
        let state = Self.loadStateLogged()
        return state.items
            .filter { !$0.deleted }
            .map(ItemEntity.init(from:))
    }
}
