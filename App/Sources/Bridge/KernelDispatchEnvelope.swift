import Foundation

enum KernelDispatchEnvelope {
    static func podcast(namespace: String, json: String, correlationId: String) -> [UInt8]? {
        switch namespace {
        case "podcast":
            return GeneratedActionBuilders.podcastJson(correlationId: correlationId, json: json)
        case "podcast.agent":
            return GeneratedActionBuilders.podcastAgentJson(correlationId: correlationId, json: json)
        case "podcast.categorize":
            return GeneratedActionBuilders.podcastCategorizeJson(correlationId: correlationId, json: json)
        case "podcast.chapters":
            return GeneratedActionBuilders.podcastChaptersJson(correlationId: correlationId, json: json)
        case "podcast.clip":
            return GeneratedActionBuilders.podcastClipJson(correlationId: correlationId, json: json)
        case "podcast.identity":
            return GeneratedActionBuilders.podcastIdentityJson(correlationId: correlationId, json: json)
        case "podcast.inbox":
            return GeneratedActionBuilders.podcastInboxJson(correlationId: correlationId, json: json)
        case "podcast.knowledge":
            return GeneratedActionBuilders.podcastKnowledgeJson(correlationId: correlationId, json: json)
        case "podcast.memory":
            return GeneratedActionBuilders.podcastMemoryJson(correlationId: correlationId, json: json)
        case "podcast.picks":
            return GeneratedActionBuilders.podcastPicksJson(correlationId: correlationId, json: json)
        case "podcast.player":
            return GeneratedActionBuilders.podcastPlayerJson(correlationId: correlationId, json: json)
        case "podcast.publish":
            return GeneratedActionBuilders.podcastPublishJson(correlationId: correlationId, json: json)
        case "podcast.queue":
            return GeneratedActionBuilders.podcastQueueJson(correlationId: correlationId, json: json)
        case "podcast.settings":
            return GeneratedActionBuilders.podcastSettingsJson(correlationId: correlationId, json: json)
        case "podcast.siri":
            return GeneratedActionBuilders.podcastSiriJson(correlationId: correlationId, json: json)
        case "podcast.social":
            return GeneratedActionBuilders.podcastSocialJson(correlationId: correlationId, json: json)
        case "podcast.tasks":
            return GeneratedActionBuilders.podcastTasksJson(correlationId: correlationId, json: json)
        case "podcast.voice":
            return GeneratedActionBuilders.podcastVoiceJson(correlationId: correlationId, json: json)
        default:
            return nil
        }
    }

    static func blossomUpload(body: [String: Any], correlationId: String) -> [UInt8]? {
        guard let filePath = body["file_path"] as? String, !filePath.isEmpty else {
            return nil
        }
        return NmpActionBuilders.blossomUpload(
            correlationId: correlationId,
            filePath: filePath,
            contentType: body["content_type"] as? String,
            servers: body["servers"] as? [String],
            signerPubkey: body["signer_pubkey"] as? String
        )
    }
}
