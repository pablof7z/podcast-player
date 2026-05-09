import Foundation

// MARK: - ChatMessage

/// A single message in the agent chat transcript.
/// Uses manual `Codable` because `Role` carries associated values that require
/// a discriminated-union encoding (roleType + optional batchID/batchCount).
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: Equatable {
        case user
        case assistant
        case toolBatch(batchID: UUID, count: Int)
        case error
    }

    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case roleType
        case batchID
        case batchCount
        case text
        case timestamp
    }

    private enum RoleType: String, Codable {
        case user
        case assistant
        case toolBatch
        case error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        let type = try c.decode(RoleType.self, forKey: .roleType)
        switch type {
        case .user:
            self.role = .user
        case .assistant:
            self.role = .assistant
        case .error:
            self.role = .error
        case .toolBatch:
            let batchID = try c.decode(UUID.self, forKey: .batchID)
            let count = try c.decode(Int.self, forKey: .batchCount)
            self.role = .toolBatch(batchID: batchID, count: count)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(timestamp, forKey: .timestamp)
        switch role {
        case .user:
            try c.encode(RoleType.user, forKey: .roleType)
        case .assistant:
            try c.encode(RoleType.assistant, forKey: .roleType)
        case .error:
            try c.encode(RoleType.error, forKey: .roleType)
        case .toolBatch(let batchID, let count):
            try c.encode(RoleType.toolBatch, forKey: .roleType)
            try c.encode(batchID, forKey: .batchID)
            try c.encode(count, forKey: .batchCount)
        }
    }
}
