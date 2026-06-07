package io.f7z.podcast

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class OpenRouterWhisperIntent(
    @SerialName("audio_url") val audioUrl: String,
    @SerialName("language_hint") val languageHint: String? = null,
)

@Serializable
data class OpenRouterWhisperEnvelope(
    val result: OpenRouterWhisperResult? = null,
    val error: OpenRouterWhisperBackendError? = null,
)

@Serializable
data class OpenRouterWhisperBackendError(
    val kind: String,
    val message: String? = null,
    @SerialName("status_code") val statusCode: Int? = null,
)

@Serializable
data class OpenRouterWhisperResult(
    val task: String? = null,
    val language: String? = null,
    val duration: Double? = null,
    val text: String? = null,
    val segments: List<OpenRouterWhisperSegment> = emptyList(),
    val model: String = "",
    @SerialName("latency_ms") val latencyMs: Long = 0,
)

@Serializable
data class OpenRouterWhisperSegment(
    val id: Long? = null,
    val start: Double,
    val end: Double,
    val text: String,
)

object OpenRouterWhisperTranscriptionService {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    suspend fun transcribe(
        bridge: KernelBridge,
        intent: OpenRouterWhisperIntent,
    ): OpenRouterWhisperResult = withContext(Dispatchers.IO) {
        val request = json.encodeToString(OpenRouterWhisperIntent.serializer(), intent)
        val response = bridge.openRouterWhisperTranscribe(request)
            ?: throw IllegalStateException("OpenRouter Whisper returned null")
        val envelope = json.decodeFromString(OpenRouterWhisperEnvelope.serializer(), response)
        envelope.error?.let { error ->
            val suffix = error.statusCode?.let { " (HTTP $it)" }.orEmpty()
            throw IllegalStateException((error.message ?: error.kind) + suffix)
        }
        envelope.result ?: throw IllegalStateException("OpenRouter Whisper response missing result")
    }
}
