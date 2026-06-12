package io.f7z.podcast.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.f7z.podcast.AgentPickSummary
import io.f7z.podcast.KernelBridge

/**
 * AI Picks rail — a horizontal card stack of kernel-projected picks.
 *
 * Thin-shell (D5/D7/D8): renders [AgentPickSummary] rows from the
 * `podcast.misc` domain frame. The kernel owns all ranking logic;
 * this composable only renders the projected state and dispatches ops.
 *
 * Dispatch ops (source of truth: `ffi/actions/picks_module.rs`):
 *  - Tap pick card  → `podcast.player` `{"op":"play","episode_id":"…"}`
 *  - Refresh button → `podcast.picks`  `{"op":"refresh"}`
 *
 * The rail is hidden when [picks] is empty so the Home screen degrades
 * gracefully before the first projection arrives.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PicksRail(
    picks: List<AgentPickSummary>,
    bridge: KernelBridge,
    modifier: Modifier = Modifier,
) {
    if (picks.isEmpty()) return

    Column(modifier = modifier) {
        PicksRailHeader(bridge = bridge)
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(picks, key = { it.episodeId }) { pick ->
                PickCard(pick = pick, bridge = bridge)
            }
        }
    }
}

@Composable
private fun PicksRailHeader(bridge: KernelBridge) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "AI Picks",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
        )
        IconButton(
            onClick = {
                PodcastActionDispatcher.dispatch(
                    bridge = bridge,
                    namespace = PodcastNamespace.PICKS,
                    payload = PicksRefreshPayload(),
                )
            },
        ) {
            Icon(
                imageVector = Icons.Filled.Refresh,
                contentDescription = "Refresh AI picks",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickCard(
    pick: AgentPickSummary,
    bridge: KernelBridge,
) {
    Card(
        onClick = {
            PodcastActionDispatcher.dispatch(
                bridge = bridge,
                namespace = PodcastNamespace.PLAYER,
                payload = PlayPayload(episodeId = pick.episodeId),
            )
        },
        modifier = Modifier.width(200.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            ArtworkPlaceholder(size = 56)
            Text(
                text = pick.episodeTitle,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = pick.podcastTitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (pick.pickReason.isNotBlank()) {
                SuggestionChip(
                    onClick = {},
                    label = {
                        Text(
                            text = pick.pickReason,
                            style = MaterialTheme.typography.labelSmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    modifier = Modifier.size(height = 24.dp, width = 176.dp),
                    colors = SuggestionChipDefaults.suggestionChipColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    ),
                )
            }
        }
    }
}
