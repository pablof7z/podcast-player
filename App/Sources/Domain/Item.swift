import Foundation

// MARK: - Anchor
// Polymorphic reference target — links notes/items to their context.
// Discriminated union serialized as { "kind": "...", "id": "..." } for JSON round-trip.

enum Anchor: Codable, Hashable, Sendable {
    case item(id: UUID)
    case note(id: UUID)
    /// A note attached directly to a Friend (not to one of their items).
    case friend(id: UUID)

    private enum Kind: String, Codable { case item, note, friend }
    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .item:   self = .item(id: try c.decode(UUID.self, forKey: .id))
        case .note:   self = .note(id: try c.decode(UUID.self, forKey: .id))
        case .friend: self = .friend(id: try c.decode(UUID.self, forKey: .id))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .item(let id):   try c.encode(Kind.item,   forKey: .kind); try c.encode(id, forKey: .id)
        case .note(let id):   try c.encode(Kind.note,   forKey: .kind); try c.encode(id, forKey: .id)
        case .friend(let id): try c.encode(Kind.friend, forKey: .kind); try c.encode(id, forKey: .id)
        }
    }
}

// MARK: - Item

enum ItemStatus: String, Codable, Hashable, Sendable {
    case pending, done, dropped
}

enum ItemSource: String, Codable, Hashable, Sendable {
    case manual, voice, agent
}

/// How often a reminder notification repeats.
///
/// - `none` — fires once (the default; matches legacy behaviour).
/// - `daily` — fires every day at the reminder time.
/// - `weekdays` — fires Monday–Friday at the reminder time.
/// - `weekly` — fires once a week on the same weekday.
/// - `monthly` — fires once a month on the same day-of-month.
enum ItemRecurrence: String, Codable, Hashable, Sendable, CaseIterable {
    case none, daily, weekdays, weekly, monthly

    /// Human-readable label shown in the Picker and reminder badge.
    var label: String {
        switch self {
        case .none:     return "Never"
        case .daily:    return "Every Day"
        case .weekdays: return "Weekdays"
        case .weekly:   return "Every Week"
        case .monthly:  return "Every Month"
        }
    }

    /// Short label used in the reminder row badge.
    var shortLabel: String {
        switch self {
        case .none:     return ""
        case .daily:    return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly:   return "Weekly"
        case .monthly:  return "Monthly"
        }
    }
}

struct Item: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var details: String
    var status: ItemStatus
    var source: ItemSource
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool
    var requestedByFriendID: UUID?
    var requestedByDisplayName: String?
    var reminderAt: Date?
    /// How often the reminder notification repeats. Defaults to `.none` (fire once).
    var recurrence: ItemRecurrence
    var isPriority: Bool
    /// Optional due date — distinct from `reminderAt`.
    /// `reminderAt` fires a notification; `dueAt` is metadata-only and drives
    /// the overdue badge and filter. Both can exist independently.
    var dueAt: Date?
    /// Free-form tags for grouping and filtering items (e.g. "work", "home", "urgent").
    /// Each tag is a trimmed, lowercased string. Duplicates are not stored.
    var tags: [String]
    /// Optional color label for visual grouping. Defaults to `.none` (no stripe).
    var colorTag: ItemColorTag
    /// Optional estimated time to complete this item, in minutes.
    /// `nil` means no estimate. `0` is treated the same as `nil`.
    var estimatedMinutes: Int?
    /// When `true` the item is pinned to the top of the list above all other sections.
    var isPinned: Bool

    /// Human-readable representation of `estimatedMinutes` for display in chips
    /// and rows. Returns `nil` when no estimate is set or when the value is zero.
    var estimatedDurationLabel: String? {
        guard let mins = estimatedMinutes, mins > 0 else { return nil }
        if mins < 60 {
            return "~\(mins) min"
        }
        let hours = mins / 60
        let remainder = mins % 60
        if remainder == 0 {
            return "~\(hours)h"
        }
        return "~\(hours)h \(remainder)m"
    }

    /// `true` when the item is pending and its due date is in the past.
    var isOverdue: Bool {
        guard status == .pending, let due = dueAt else { return false }
        return due < Date()
    }

    init(title: String, source: ItemSource = .manual) {
        self.id = UUID()
        self.title = title
        self.details = ""
        self.status = .pending
        self.source = source
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deleted = false
        self.recurrence = .none
        self.isPriority = false
        self.dueAt = nil
        self.tags = []
        self.colorTag = .none
        self.isPinned = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, details, status, source, createdAt, updatedAt, deleted
        case requestedByFriendID, requestedByDisplayName
        case reminderAt, recurrence, isPriority, dueAt, tags, colorTag, estimatedMinutes, isPinned
    }

    // Forward-compat: every field decoded with `decodeIfPresent` so adding
    // new fields never breaks decode of older persisted state.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        status = try c.decodeIfPresent(ItemStatus.self, forKey: .status) ?? .pending
        source = try c.decodeIfPresent(ItemSource.self, forKey: .source) ?? .manual
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        requestedByFriendID = try c.decodeIfPresent(UUID.self, forKey: .requestedByFriendID)
        requestedByDisplayName = try c.decodeIfPresent(String.self, forKey: .requestedByDisplayName)
        reminderAt = try c.decodeIfPresent(Date.self, forKey: .reminderAt)
        recurrence = try c.decodeIfPresent(ItemRecurrence.self, forKey: .recurrence) ?? .none
        isPriority = try c.decodeIfPresent(Bool.self, forKey: .isPriority) ?? false
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        colorTag = try c.decodeIfPresent(ItemColorTag.self, forKey: .colorTag) ?? .none
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}
