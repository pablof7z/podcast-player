import WidgetKit
import Foundation

// MARK: - Minimal shadow types
//
// The widget runs in a separate process and cannot import the App target.
// These lightweight structs mirror the subset of AppState fields needed
// to render pending-items data. They must stay in sync with Domain/Item.swift
// and Domain/AppState.swift whenever those types change.

struct WidgetItem: Codable, Identifiable {
    var id: UUID
    var title: String
    var isPriority: Bool
    var isPinned: Bool
    var deleted: Bool
    var status: String       // "pending" | "done" | "dropped"
    var createdAt: Date
    /// Optional estimated completion time in minutes; mirrors `Item.estimatedMinutes`.
    var estimatedMinutes: Int?

    var isPending: Bool { status == "pending" && !deleted }

    private enum CodingKeys: String, CodingKey {
        case id, title, isPriority, isPinned, deleted, status, createdAt, estimatedMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isPriority = try c.decodeIfPresent(Bool.self, forKey: .isPriority) ?? false
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.distantPast
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
    }
}

struct WidgetAppState: Codable {
    var items: [WidgetItem]
    /// User-defined display order for active items; mirrors `AppState.itemOrder`.
    var itemOrder: [UUID]
    init() { items = []; itemOrder = [] }

    private enum CodingKeys: String, CodingKey { case items, itemOrder }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([WidgetItem].self, forKey: .items) ?? []
        itemOrder = try c.decodeIfPresent([UUID].self, forKey: .itemOrder) ?? []
    }

    /// Active (pending, non-deleted) items sorted by the same rule as
    /// `AppStateStore.activeItems`: priority-first, then user-defined drag order,
    /// then `createdAt` for items not in `itemOrder`.
    var sortedPendingItems: [WidgetItem] {
        let orderIndex: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: itemOrder.enumerated().map { ($0.element, $0.offset) }
        )
        return items.filter(\.isPending).sorted { lhs, rhs in
            if lhs.isPriority != rhs.isPriority { return lhs.isPriority }
            let li = orderIndex[lhs.id]
            let ri = orderIndex[rhs.id]
            switch (li, ri) {
            case let (.some(l), .some(r)): return l < r
            case (.some, .none):           return true
            case (.none, .some):           return false
            case (.none, .none):           return lhs.createdAt < rhs.createdAt
            }
        }
    }
}

// MARK: - Persistence (widget side)

enum WidgetPersistence {
    static let stateKey = "apptemplate.state.v1"

    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.pablofernandez.apptemplate"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func loadState() -> WidgetAppState {
        guard let data = defaults.data(forKey: stateKey) else { return WidgetAppState() }
        return (try? decoder.decode(WidgetAppState.self, from: data)) ?? WidgetAppState()
    }
}

// MARK: - Preview helpers

extension WidgetItem {
    static func preview(_ title: String, priority: Bool) -> WidgetItem {
        var item = WidgetItem()
        item.title = title
        item.isPriority = priority
        return item
    }

    // memberwise-style init for previews (can't use default since CodingKeys covers all)
    init() {
        id = UUID()
        title = ""
        isPriority = false
        isPinned = false
        deleted = false
        status = "pending"
        createdAt = Date()
        estimatedMinutes = nil
    }
}
