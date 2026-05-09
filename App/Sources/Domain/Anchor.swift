import Foundation

// MARK: - Anchor
// Polymorphic reference target — links notes to their context.
// Discriminated union serialized as { "kind": "...", "id": "..." } for JSON round-trip.

enum Anchor: Codable, Hashable, Sendable {
    case note(id: UUID)
    /// A note attached directly to a Friend.
    case friend(id: UUID)

    private enum Kind: String, Codable { case note, friend }
    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .note:   self = .note(id: try c.decode(UUID.self, forKey: .id))
        case .friend: self = .friend(id: try c.decode(UUID.self, forKey: .id))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .note(let id):   try c.encode(Kind.note,   forKey: .kind); try c.encode(id, forKey: .id)
        case .friend(let id): try c.encode(Kind.friend, forKey: .kind); try c.encode(id, forKey: .id)
        }
    }
}
