package io.f7z.podcast.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.f7z.podcast.ClipActions
import io.f7z.podcast.ClipSummary
import io.f7z.podcast.KernelBridge
import io.f7z.podcast.PodcastSnapshot
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Global clip list screen — shows all clips the user has saved, newest-first.
 *
 * Mirrors iOS `ClippingsView`:
 *  - Clips sourced from `snapshot.clips` (the `podcast.misc` domain projection).
 *  - Empty state when no clips exist yet.
 *  - Swipe-to-delete calls `ClipActions.delete` via [KernelBridge]; the clip
 *    disappears on the next snapshot tick (kernel owns state).
 *  - Video/share export is explicitly OUT OF SCOPE for this PR — deferred to
 *    a follow-up (see PR description and docs/BACKLOG.md).
 *
 * Wire contract: `snapshot.clips` is a `List<ClipSummary>` decoded from the
 * `podcast.misc` push frame. Fields verified against
 * `apps/nmp-app-podcast/src/ffi/projections/clips.rs::ClipSummary`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClipListScreen(
    snapshot: PodcastSnapshot?,
    bridge: KernelBridge,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // Sort newest-first by created_at (kernel emits insertion order; UI applies sort).
    val clips = (snapshot?.clips ?: emptyList())
        .sortedByDescending { it.createdAt }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Clippings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { inner ->
        if (clips.isEmpty()) {
            ClipListEmptyState(modifier = Modifier.padding(inner))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(inner),
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                items(clips, key = { it.id }) { clip ->
                    SwipeToDeleteClipRow(
                        clip = clip,
                        onDelete = {
                            ClipActions.delete(bridge, clip.id)
                            scope.launch {
                                snackbarHostState.showSnackbar("Clip deleted")
                            }
                        },
                    )
                }
            }
        }
    }
}

// ── Empty state ───────────────────────────────────────────────────────────────

@Composable
private fun ClipListEmptyState(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(horizontal = 32.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.ContentCut,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "No Clippings Yet",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = "Open an episode and use the Create Clip button to save a moment.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

// ── Clip row with swipe-to-delete ────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDeleteClipRow(
    clip: ClipSummary,
    onDelete: () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                true
            } else {
                false
            }
        },
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = "Delete clip",
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        },
    ) {
        ClipRow(clip = clip)
    }
}

@Composable
private fun ClipRow(clip: ClipSummary, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        // Title line: user-given title or episode title fallback
        Text(
            text = clip.title ?: clip.episodeTitle.ifBlank { "Untitled clip" },
            style = MaterialTheme.typography.bodyLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        // Podcast title
        if (clip.podcastTitle.isNotBlank()) {
            Text(
                text = clip.podcastTitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        // Time range + date
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = formatClipRange(clip.startSecs, clip.endSecs),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "•",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = formatClipDate(clip.createdAt),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ── Formatters ────────────────────────────────────────────────────────────────

/** Format start→end as "1:23 → 2:45" (mm:ss or h:mm:ss). */
private fun formatClipRange(startSecs: Double, endSecs: Double): String =
    "${formatTimecode(startSecs)} → ${formatTimecode(endSecs)}"

private fun formatTimecode(secs: Double): String {
    val total = secs.roundToInt().coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s)
    else "%d:%02d".format(m, s)
}

private val DATE_FORMAT = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())

private fun formatClipDate(unixSecs: Long): String =
    DATE_FORMAT.format(Date(unixSecs * 1000L))
