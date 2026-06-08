package io.f7z.podcast.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.f7z.podcast.ElevenLabsVoice
import io.f7z.podcast.KernelBridge
import io.f7z.podcast.SettingsSnapshot

@Composable
internal fun SttProviderButton(
    title: String,
    detail: String,
    provider: String,
    selectedProvider: String,
    keyPresent: Boolean,
    bridge: KernelBridge,
) {
    val selected = selectedProvider == provider
    val detailText = if (keyPresent) detail else "$detail Key not connected."
    val label = if (selected) "Selected" else "Use"
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            )
            Text(
                text = detailText,
                style = MaterialTheme.typography.bodySmall,
                color = if (keyPresent) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.error
                },
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (selected) {
            Button(onClick = {}, enabled = false) { Text(label) }
        } else {
            OutlinedButton(
                onClick = {
                    PodcastActionDispatcher.dispatch(
                        bridge = bridge,
                        namespace = PodcastNamespace.SETTINGS,
                        payload = SetSttProviderPayload(provider = provider),
                    )
                },
            ) { Text(label) }
        }
    }
}

@Composable
internal fun SpeechModelChooser(
    title: String,
    current: String,
    options: List<ModelOption>,
    onSelect: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text = title, style = MaterialTheme.typography.bodyLarge)
        visibleModelOptions(options, current).forEach { option ->
            val selected = option.id == current
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = option.label,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    )
                    Text(
                        text = option.id,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (selected) {
                    Button(onClick = {}, enabled = false) { Text("Selected") }
                } else {
                    OutlinedButton(onClick = { onSelect(option.id) }) { Text("Use") }
                }
            }
        }
    }
}

private fun visibleModelOptions(options: List<ModelOption>, current: String): List<ModelOption> {
    if (current.isBlank() || options.any { it.id == current }) {
        return options
    }
    return listOf(ModelOption(current, "Current model")) + options
}

@Composable
internal fun ElevenLabsVoiceEditor(
    settings: SettingsSnapshot,
    bridge: KernelBridge,
    voices: List<ElevenLabsVoice>,
    isLoading: Boolean,
    errorMessage: String?,
    onRefresh: () -> Unit,
) {
    var showVoiceBrowser by remember { mutableStateOf(false) }
    val selectedVoice = voices.firstOrNull { it.voiceId == settings.elevenLabsVoiceId }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = "ElevenLabs voice", style = MaterialTheme.typography.bodyLarge)
        Text(
            text = selectedVoiceLabel(settings, selectedVoice),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.primary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        val voiceId = settings.elevenLabsVoiceId
        if (voiceId.isNotBlank()) {
            Text(
                text = voiceId,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (isLoading && voices.isEmpty()) {
            Text(
                text = "Loading voice catalog",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (errorMessage != null) {
            Text(
                text = errorMessage,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            OutlinedButton(onClick = onRefresh, enabled = !isLoading) {
                Text("Refresh")
            }
            Button(
                onClick = {
                    if (voices.isEmpty() && !isLoading) {
                        onRefresh()
                    }
                    showVoiceBrowser = true
                },
            ) {
                Text("Browse voices")
            }
        }
    }

    if (showVoiceBrowser) {
        ElevenLabsVoiceSelectorSheet(
            voices = voices,
            currentVoiceId = settings.elevenLabsVoiceId,
            currentVoiceName = settings.elevenLabsVoiceName,
            isLoading = isLoading,
            errorMessage = errorMessage,
            onRefresh = onRefresh,
            onDismiss = { showVoiceBrowser = false },
            onSelect = { voiceId, voiceName ->
                PodcastActionDispatcher.dispatch(
                    bridge = bridge,
                    namespace = PodcastNamespace.SETTINGS,
                    payload = SetElevenLabsVoicePayload(
                        voiceId = voiceId,
                        voiceName = voiceName,
                    ),
                )
                showVoiceBrowser = false
            },
        )
    }
}

private fun selectedVoiceLabel(settings: SettingsSnapshot, voice: ElevenLabsVoice?): String {
    if (settings.elevenLabsVoiceName.isNotBlank()) return settings.elevenLabsVoiceName
    if (voice != null) return voice.displayName
    if (settings.elevenLabsVoiceId.isNotBlank()) return settings.elevenLabsVoiceId
    return "No voice selected"
}
