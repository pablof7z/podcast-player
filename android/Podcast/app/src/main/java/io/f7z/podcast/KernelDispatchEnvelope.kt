package io.f7z.podcast

import org.nmp.android.GeneratedActionBuilders

object KernelDispatchEnvelope {
    fun podcast(namespace: String, json: String, correlationId: String): ByteArray? =
        when (namespace) {
            "podcast" -> GeneratedActionBuilders.podcastJson(correlationId, json)
            "podcast.agent" -> GeneratedActionBuilders.podcastAgentJson(correlationId, json)
            "podcast.categorize" -> GeneratedActionBuilders.podcastCategorizeJson(correlationId, json)
            "podcast.chapters" -> GeneratedActionBuilders.podcastChaptersJson(correlationId, json)
            "podcast.clip" -> GeneratedActionBuilders.podcastClipJson(correlationId, json)
            "podcast.identity" -> GeneratedActionBuilders.podcastIdentityJson(correlationId, json)
            "podcast.inbox" -> GeneratedActionBuilders.podcastInboxJson(correlationId, json)
            "podcast.knowledge" -> GeneratedActionBuilders.podcastKnowledgeJson(correlationId, json)
            "podcast.memory" -> GeneratedActionBuilders.podcastMemoryJson(correlationId, json)
            "podcast.picks" -> GeneratedActionBuilders.podcastPicksJson(correlationId, json)
            "podcast.player" -> GeneratedActionBuilders.podcastPlayerJson(correlationId, json)
            "podcast.publish" -> GeneratedActionBuilders.podcastPublishJson(correlationId, json)
            "podcast.queue" -> GeneratedActionBuilders.podcastQueueJson(correlationId, json)
            "podcast.settings" -> GeneratedActionBuilders.podcastSettingsJson(correlationId, json)
            "podcast.siri" -> GeneratedActionBuilders.podcastSiriJson(correlationId, json)
            "podcast.social" -> GeneratedActionBuilders.podcastSocialJson(correlationId, json)
            "podcast.tasks" -> GeneratedActionBuilders.podcastTasksJson(correlationId, json)
            "podcast.voice" -> GeneratedActionBuilders.podcastVoiceJson(correlationId, json)
            else -> null
        }
}
