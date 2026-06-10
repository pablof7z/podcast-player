import SwiftUI

// MARK: - FeedbackCategory

enum FeedbackCategory: String, Codable, CaseIterable, Identifiable {
    case bug = "Bug"
    case featureRequest = "Feature Request"
    case question = "Question"
    case praise = "Praise"

    var id: String { rawValue }

    var tagValue: String {
        switch self {
        case .bug: "bug"
        case .featureRequest: "feature-request"
        case .question: "question"
        case .praise: "praise"
        }
    }

    /// Map the kernel-resolved canonical category tag value (`bug`,
    /// `feature-request`, `question`, `praise`) to the enum, defaulting to
    /// `.bug`. The Nostr tag parsing now happens kernel-side (#354).
    init(tagValue: String) {
        self = Self.allCases.first { $0.tagValue == tagValue } ?? .bug
    }

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
    var id: String { eventID }
    var eventID: String
    var authorPubkey: String
    var category: FeedbackCategory
    var content: String
    var attachedImage: UIImage?
    var title: String?
    var summary: String?
    var statusLabel: String?
    var replies: [FeedbackReply] = []
    var createdAt: Date = Date()

    init(
        eventID: String = "local-\(UUID().uuidString)",
        authorPubkey: String = "",
        category: FeedbackCategory,
        content: String,
        attachedImage: UIImage? = nil,
        title: String? = nil,
        summary: String? = nil,
        statusLabel: String? = nil,
        replies: [FeedbackReply] = [],
        createdAt: Date = Date()
    ) {
        self.eventID = eventID
        self.authorPubkey = authorPubkey
        self.category = category
        self.content = content
        self.attachedImage = attachedImage
        self.title = title
        self.summary = summary
        self.statusLabel = statusLabel
        self.replies = replies
        self.createdAt = createdAt
    }

    /// Build from the kernel's resolved feedback-thread projection (#354).
    /// All Nostr reduction (NIP-10 threading, kind:513 supersession, tag
    /// parsing) happened kernel-side; this only maps fields + attaches the
    /// local-only image.
    init(dto: FeedbackThreadDTO, localPubkey: String?, attachedImage: UIImage? = nil) {
        self.eventID = dto.eventId
        self.authorPubkey = dto.authorPubkey
        self.category = FeedbackCategory(tagValue: dto.category)
        self.content = dto.content
        self.attachedImage = attachedImage
        self.title = dto.title
        self.summary = dto.summary
        self.statusLabel = dto.statusLabel
        self.replies = dto.replies.map { FeedbackReply(dto: $0, localPubkey: localPubkey) }
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(dto.createdAt))
    }
}

// MARK: - FeedbackReply

struct FeedbackReply: Identifiable {
    var id: String { eventID }
    var eventID: String
    var authorPubkey: String
    var content: String
    var isFromMe: Bool
    var createdAt: Date = Date()

    init(dto: FeedbackReplyDTO, localPubkey: String?) {
        eventID = dto.eventId
        authorPubkey = dto.authorPubkey
        content = dto.content
        isFromMe = dto.authorPubkey == localPubkey
        createdAt = Date(timeIntervalSince1970: TimeInterval(dto.createdAt))
    }

    /// Optimistic reply synthesized from inputs (the kernel publish path is
    /// fire-and-forget, so there is no returned signed event to build from).
    init(
        eventID: String = "local-\(UUID().uuidString)",
        authorPubkey: String,
        content: String,
        isFromMe: Bool,
        createdAt: Date = Date()
    ) {
        self.eventID = eventID
        self.authorPubkey = authorPubkey
        self.content = content
        self.isFromMe = isFromMe
        self.createdAt = createdAt
    }
}
