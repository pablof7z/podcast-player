import SwiftUI

// MARK: - FeedbackCategory

enum FeedbackCategory: String, Codable, CaseIterable, Identifiable {
    case bug = "Bug"
    case featureRequest = "Feature Request"
    case question = "Question"
    case praise = "Praise"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bug: "ant.fill"
        case .featureRequest: "lightbulb.fill"
        case .question: "questionmark.circle.fill"
        case .praise: "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .bug: .red
        case .featureRequest: .blue
        case .question: .purple
        case .praise: .pink
        }
    }
}

// MARK: - FeedbackThread

struct FeedbackThread: Identifiable {
    var id: UUID = UUID()
    var category: FeedbackCategory
    var content: String
    var attachedImage: UIImage?
    var title: String?
    var summary: String?
    var statusLabel: String?
    var replies: [FeedbackReply] = []
    var createdAt: Date = Date()
}

extension FeedbackThread: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, category, content, title, summary, statusLabel, replies, createdAt
        // attachedImage is intentionally excluded — UIImage is not Codable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        category = try c.decode(FeedbackCategory.self, forKey: .category)
        content = try c.decode(String.self, forKey: .content)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel)
        replies = try c.decode([FeedbackReply].self, forKey: .replies)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(statusLabel, forKey: .statusLabel)
        try c.encode(replies, forKey: .replies)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - FeedbackReply

struct FeedbackReply: Identifiable, Codable {
    var id: UUID = UUID()
    var content: String
    var isFromMe: Bool
    var createdAt: Date = Date()
}
