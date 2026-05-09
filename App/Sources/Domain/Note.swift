import Foundation

// MARK: - Note

enum NoteKind: String, Codable, Hashable, Sendable {
    case free
    case reflection
    case systemEvent
}

struct Note: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var text: String
    var kind: NoteKind
    var target: Anchor?
    var createdAt: Date
    var deleted: Bool

    init(text: String, kind: NoteKind = .free, target: Anchor? = nil) {
        self.id = UUID()
        self.text = text
        self.kind = kind
        self.target = target
        self.createdAt = Date()
        self.deleted = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, kind, target, createdAt, deleted
    }

    // Forward-compat: every field decoded with `decodeIfPresent` so adding
    // new fields never breaks decode of older persisted state.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        kind = try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .free
        target = try c.decodeIfPresent(Anchor.self, forKey: .target)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
}
