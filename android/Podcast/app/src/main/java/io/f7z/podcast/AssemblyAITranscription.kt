package io.f7z.podcast

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class AssemblyAITranscriptionIntent(
    @SerialName("audio_url") val audioUrl: String,
    @SerialName("language_hint") val languageHint: String? = null,
)

@Serializable
data class AssemblyAITranscriptionEnvelope(
    val result: AssemblyAITranscriptionResult? = null,
    val error: AssemblyAITranscriptionBackendError? = null,
)

@Serializable
data class AssemblyAITranscriptionBackendError(
    val kind: String,
    val message: String? = null,
    @SerialName("status_code") val statusCode: Int? = null,
)

@Serializable
data class AssemblyAITranscriptionResult(
    val id: String? = null,
    val status: String? = null,
    @SerialName("audio_url") val audioUrl: String? = null,
    @SerialName("audio_duration") val audioDuration: Double? = null,
    @SerialName("language_code") val languageCode: String? = null,
    val text: String? = null,
    val error: String? = null,
    val words: List<AssemblyAIWord> = emptyList(),
    val utterances: List<AssemblyAIUtterance> = emptyList(),
    val usage: AssemblyAIUsage? = null,
    val model: String = "",
    @SerialName("latency_ms") val latencyMs: Long = 0,
)

@Serializable
data class AssemblyAIUsage(
    val cost: Double? = null,
    val seconds: Double? = null,
    @SerialName("input_tokens") val inputTokens: Long? = null,
    @SerialName("output_tokens") val outputTokens: Long? = null,
    @SerialName("total_tokens") val totalTokens: Long? = null,
)

@Serializable
data class AssemblyAIUtterance(
    val start: Long,
    val end: Long,
    val text: String,
    val confidence: Double? = null,
    val speaker: String? = null,
    val words: List<AssemblyAIWord> = emptyList(),
)

@Serializable
data class AssemblyAIWord(
    val start: Long,
    val end: Long,
    val text: String,
    val confidence: Double? = null,
    val speaker: String? = null,
)

object AssemblyAITranscriptionService {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    suspend fun transcribe(
        bridge: KernelBridge,
        intent: AssemblyAITranscriptionIntent,
    ): AssemblyAITranscriptionResult = withContext(Dispatchers.IO) {
        val request = json.encodeToString(AssemblyAITranscriptionIntent.serializer(), intent)
        val response = bridge.assemblyAITranscribe(request)
            ?: throw IllegalStateException("AssemblyAI returned null")
        val envelope = json.decodeFromString(AssemblyAITranscriptionEnvelope.serializer(), response)
        envelope.error?.let { error ->
            val suffix = error.statusCode?.let { " (HTTP $it)" }.orEmpty()
            throw IllegalStateException((error.message ?: error.kind) + suffix)
        }
        envelope.result ?: throw IllegalStateException("AssemblyAI response missing result")
    }
}
