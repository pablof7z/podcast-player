package io.f7z.podcast.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.f7z.podcast.NostrConversationDto
import io.f7z.podcast.NostrConversationTurnDto
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Nostr Conversation Detail screen — iOS parity for `NostrConversationDetailView.swift`.
 *
 * Renders the full NIP-10-threaded transcript in a Slack-style layout:
 *  - All bubbles left-aligned in a single column (no right-side outbound bubbles —
 *    matches the iOS Slack-style where all messages anchor to the left).
 *  - Avatar + sender header shown for the first turn in a burst (pubkey change
 *    or > 5 min gap), suppressed for continuation turns.
 *  - Inbound turns use `surfaceVariant`; outbound turns use
 *    `primaryContainer` at 18 % opacity to match iOS `agentSurface.opacity(0.18)`.
 *
 * The screen auto-scrolls to the bottom on first appearance (parity with iOS
 * `.defaultScrollAnchor(.bottom)`).
 *
 * No actions dispatched — read-only surface.
 *
 * Profile resolution: sender display name falls back to "Agent" for outbound
 * turns and the shortened hex pubkey for inbound turns (no resolved profile
 * cache on Android yet).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NostrConversationDetailScreen(
    conversation: NostrConversationDto,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()

    // Auto-scroll to bottom on first composition, matching iOS .defaultScrollAnchor(.bottom).
    LaunchedEffect(Unit) {
        if (conversation.turns.isNotEmpty()) {
            listState.scrollToItem(conversation.turns.lastIndex)
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Conversation") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { innerPadding ->
        if (conversation.turns.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "No messages in this conversation.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                itemsIndexed(
                    conversation.turns,
                    key = { _, turn -> turn.eventId },
                ) { index, turn ->
                    val showHeader = shouldShowHeader(conversation.turns, index)
                    NostrSlackBubble(
                        turn = turn,
                        showHeader = showHeader,
                    )
                }
            }
        }
    }
}

// ── Burst-header logic ────────────────────────────────────────────────────────

private const val BURST_GAP_SECONDS = 300L

/**
 * Show a sender header when:
 *  - It is the first turn (index == 0), or
 *  - The sender changed from the previous turn, or
 *  - More than [BURST_GAP_SECONDS] elapsed since the previous turn.
 *
 * Mirrors `NostrConversationDetailView.showHeader(at:)` exactly.
 */
private fun shouldShowHeader(turns: List<NostrConversationTurnDto>, index: Int): Boolean {
    if (index == 0) return true
    val prev = turns[index - 1]
    val curr = turns[index]
    if (prev.pubkeyHex != curr.pubkeyHex) return true
    return (curr.createdAt - prev.createdAt) > BURST_GAP_SECONDS
}

// ── Slack-style bubble ────────────────────────────────────────────────────────

@Composable
private fun NostrSlackBubble(
    turn: NostrConversationTurnDto,
    showHeader: Boolean,
    modifier: Modifier = Modifier,
) {
    val isOutbound = turn.direction == "outbound"

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 1.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Avatar slot — fixed 32 dp wide; shown only on header turns.
        if (showHeader) {
            NostrAvatarPlaceholder(modifier = Modifier.size(32.dp))
        } else {
            Spacer(modifier = Modifier.width(32.dp))
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            if (showHeader) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = displayNameForTurn(turn),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = if (isOutbound)
                            MaterialTheme.colorScheme.primary
                        else
                            MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = formatTimestamp(turn.createdAt),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Surface(
                shape = RoundedCornerShape(14.dp),
                color = if (isOutbound)
                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
                else
                    MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier.widthIn(max = 480.dp),
            ) {
                Text(
                    text = turn.content,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
        }

        // Right-side spacer so bubbles don't stretch full width (matches iOS Spacer(minLength: 0)).
        Spacer(modifier = Modifier.width(32.dp))
    }
}

// ── Display-name helper ───────────────────────────────────────────────────────

/**
 * Resolve a human-readable label for a turn's sender. When the Android
 * kernel-resolved profile cache is available this will be extended; for now:
 *  - outbound ("our" agent) → "Agent"
 *  - inbound → short hex pubkey
 *
 * Mirrors iOS `NostrSlackBubble.displayName`.
 */
private fun displayNameForTurn(turn: NostrConversationTurnDto): String =
    if (turn.direction == "outbound") "Agent" else shortHex(turn.pubkeyHex)

// ── Timestamp helper ──────────────────────────────────────────────────────────

private val shortDateFmt = SimpleDateFormat("MMM d", Locale.getDefault())
private val timeFmt = SimpleDateFormat("h:mm a", Locale.getDefault())

/**
 * Renders a compact timestamp. Within the past 24 h: time only ("3:45 PM").
 * Beyond that: abbreviated date ("Jun 1"). Mirrors iOS
 * `turn.createdAt.formatted(date: .abbreviated, time: .shortened)`.
 */
internal fun formatTimestamp(epochSeconds: Long): String {
    val ageMs = System.currentTimeMillis() - epochSeconds * 1_000L
    return if (ageMs < TimeUnit.DAYS.toMillis(1)) {
        timeFmt.format(Date(epochSeconds * 1_000L))
    } else {
        shortDateFmt.format(Date(epochSeconds * 1_000L))
    }
}
