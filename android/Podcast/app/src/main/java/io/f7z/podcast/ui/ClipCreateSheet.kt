package io.f7z.podcast.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetState
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import io.f7z.podcast.ClipActions
import io.f7z.podcast.KernelBridge
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Bottom sheet for creating a new clip from an episode.
 *
 * Analogous to iOS `ClipComposerSheet` — lets the user set start/end
 * boundaries (slider-based on Android; transcript-handle drag on iOS where
 * the full transcript is available) and an optional title, then dispatches
 * `podcast.clip.create` via [ClipActions.create].
 *
 * The new clip appears reactively in [ClipListScreen] on the next snapshot
 * tick — the kernel owns clip state and projects it back via `podcast.misc`.
 *
 * DEFERRED (out of scope for this PR):
 *  - Video/share export (`ClipVideoComposer` / `ClipShareSheet` iOS equivalents)
 *    are device-only-verifiable long-tail — tracked in docs/BACKLOG.md.
 *  - Transcript-driven handle UI (requires transcript to be fetched first).
 *
 * Wire contract verified against
 * `apps/nmp-app-podcast/src/ffi/actions/clip_module.rs::ClipAction::Create`:
 * ```json
 * {"op":"create","episode_id":"<uuid>","start_secs":N,"end_secs":N}
 * ```
 * Optional: `"title":"…"` when non-blank.
 *
 * @param episodeId     Kernel UUID string of the episode to clip.
 * @param episodeTitle  Human-readable title shown in the sheet header.
 * @param durationSecs  Known episode duration — used to clamp the slider.
 *                      Pass `null` when unknown (defaults to a 60-minute cap).
 * @param initialStartSecs Starting position pre-filled into the start slider
 *                         (e.g. current playback position). Defaults to 0.
 * @param bridge        [KernelBridge] used to dispatch the create action.
 * @param onDismiss     Called after save OR explicit cancel. The caller should
 *                      close the sheet on this callback.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClipCreateSheet(
    episodeId: String,
    episodeTitle: String,
    durationSecs: Double?,
    initialStartSecs: Double = 0.0,
    bridge: KernelBridge,
    onDismiss: () -> Unit,
) {
    val sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    // Use a 30-second default window matching iOS ClipComposerSheet bootstrapDraft.
    val effectiveDuration = durationSecs?.coerceAtLeast(1.0) ?: 3600.0
    val defaultEnd = (initialStartSecs + 30.0).coerceAtMost(effectiveDuration)

    var startSecs by remember { mutableDoubleStateOf(initialStartSecs.coerceIn(0.0, effectiveDuration)) }
    var endSecs   by remember { mutableDoubleStateOf(defaultEnd.coerceIn(0.0, effectiveDuration)) }
    var title     by remember { mutableStateOf("") }
    var isSaving  by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        ClipCreateSheetContent(
            episodeTitle = episodeTitle,
            durationSecs = effectiveDuration,
            startSecs = startSecs,
            endSecs = endSecs,
            title = title,
            isSaving = isSaving,
            onStartSecsChanged = { v ->
                startSecs = v.coerceIn(0.0, endSecs - 1.0)
            },
            onEndSecsChanged = { v ->
                endSecs = v.coerceIn(startSecs + 1.0, effectiveDuration)
            },
            onTitleChanged = { title = it },
            onSave = {
                if (!isSaving && endSecs > startSecs) {
                    isSaving = true
                    ClipActions.create(
                        bridge = bridge,
                        episodeId = episodeId,
                        startSecs = startSecs,
                        endSecs = endSecs,
                        title = title.trim().ifEmpty { null },
                    )
                    scope.launch {
                        sheetState.hide()
                        onDismiss()
                    }
                }
            },
            onCancel = {
                scope.launch {
                    sheetState.hide()
                    onDismiss()
                }
            },
        )
    }
}

// ── Sheet body — extracted for testability ────────────────────────────────────

@Composable
internal fun ClipCreateSheetContent(
    episodeTitle: String,
    durationSecs: Double,
    startSecs: Double,
    endSecs: Double,
    title: String,
    isSaving: Boolean,
    onStartSecsChanged: (Double) -> Unit,
    onEndSecsChanged: (Double) -> Unit,
    onTitleChanged: (String) -> Unit,
    onSave: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Sheet handle implied by ModalBottomSheet; no explicit drag handle needed.

        Text(
            text = "New Clip",
            style = MaterialTheme.typography.titleLarge,
        )
        Text(
            text = episodeTitle,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
        )

        Spacer(Modifier.height(4.dp))

        // ── Range section ──────────────────────────────────────────────────
        Text(
            text = "Range",
            style = MaterialTheme.typography.titleSmall,
        )
        Text(
            text = "${formatTimecodeShort(startSecs)} → ${formatTimecodeShort(endSecs)}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // Start slider
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Start",
                    style = MaterialTheme.typography.labelMedium,
                )
                Text(
                    text = formatTimecodeShort(startSecs),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Slider(
                value = startSecs.toFloat(),
                onValueChange = { onStartSecsChanged(it.toDouble()) },
                valueRange = 0f..durationSecs.toFloat(),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // End slider
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "End",
                    style = MaterialTheme.typography.labelMedium,
                )
                Text(
                    text = formatTimecodeShort(endSecs),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Slider(
                value = endSecs.toFloat(),
                onValueChange = { onEndSecsChanged(it.toDouble()) },
                valueRange = 0f..durationSecs.toFloat(),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // ── Optional title ─────────────────────────────────────────────────
        OutlinedTextField(
            value = title,
            onValueChange = onTitleChanged,
            label = { Text("Title (optional)") },
            placeholder = { Text("e.g. Key insight on metabolism") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(Modifier.height(4.dp))

        // ── Action buttons ─────────────────────────────────────────────────
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedButton(
                onClick = onCancel,
                modifier = Modifier.weight(1f),
                enabled = !isSaving,
            ) {
                Text("Cancel")
            }
            Button(
                onClick = onSave,
                modifier = Modifier.weight(1f),
                enabled = !isSaving && endSecs > startSecs,
            ) {
                Text(if (isSaving) "Saving…" else "Save Clip")
            }
        }
    }
}

// ── Shared timecode formatter (reuses pattern from EpisodeDetailScreen) ───────

private fun formatTimecodeShort(secs: Double): String {
    val total = secs.roundToInt().coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s)
    else "%d:%02d".format(m, s)
}
