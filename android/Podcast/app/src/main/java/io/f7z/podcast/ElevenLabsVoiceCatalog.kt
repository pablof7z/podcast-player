package io.f7z.podcast

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class ElevenLabsVoiceCatalogEnvelope(
    val result: ElevenLabsVoiceCatalogResult? = null,
    val error: ElevenLabsVoiceCatalogError? = null,
)

@Serializable
data class ElevenLabsVoiceCatalogResult(
    val provider: String = "elevenlabs",
    val voices: List<ElevenLabsVoice> = emptyList(),
    @SerialName("latency_ms") val latencyMs: Long = 0,
)

@Serializable
data class ElevenLabsVoiceCatalogError(
    val kind: String? = null,
    val message: String? = null,
    @SerialName("status_code") val statusCode: Int? = null,
) {
    val displayMessage: String
        get() = message ?: kind ?: "ElevenLabs voice catalog failed"
}

@Serializable
data class ElevenLabsVoice(
    @SerialName("voice_id") val voiceId: String = "",
    val name: String = "",
    val category: String = "",
    val labels: Map<String, String> = emptyMap(),
    @SerialName("preview_url") val previewUrl: String? = null,
) {
    val displayName: String
        get() = name.ifBlank { voiceId }

    val description: String
        get() = voiceDescriptionParts().joinToString(" / ")

    fun matches(query: String): Boolean {
        val terms = query.lowercase().split(Regex("\\s+")).filter { it.isNotBlank() }
        if (terms.isEmpty()) return true
        val haystack = buildList {
            add(voiceId)
            add(name)
            add(category)
            addAll(labels.values)
        }.joinToString(" ").lowercase()
        return terms.all { haystack.contains(it) }
    }

    private fun voiceDescriptionParts(): List<String> {
        val parts = mutableListOf<String>()
        if (category.isNotBlank()) {
            parts += category.replace('_', ' ')
        }
        for (key in listOf("gender", "accent", "age", "use_case", "description")) {
            val value = labels[key]?.takeIf { it.isNotBlank() } ?: continue
            parts += value.replace('_', ' ')
        }
        return parts
    }
}

object ElevenLabsVoiceCatalogService {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    suspend fun fetchCatalog(bridge: KernelBridge): ElevenLabsVoiceCatalogResult =
        withContext(Dispatchers.IO) {
            val response = bridge.elevenLabsVoiceCatalog()
                ?: throw IllegalStateException("ElevenLabs voice catalog returned null")
            val envelope = json.decodeFromString<ElevenLabsVoiceCatalogEnvelope>(response)
            envelope.error?.let { throw IllegalStateException(it.displayMessage) }
            envelope.result ?: throw IllegalStateException("ElevenLabs voice catalog response missing result")
        }
}
