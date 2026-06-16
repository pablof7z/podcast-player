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
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.f7z.podcast.ContactSummaryDto
import io.f7z.podcast.KernelBridge
import io.f7z.podcast.PodcastSnapshot

/**
 * Following screen — read-only NIP-02 follow list (iOS social parity, slice 1).
 *
 * Renders the kernel-projected follow list from `snapshot.following` (the
 * `podcast.social` domain frame's `SocialSnapshot.following` field).
 *
 * Slice 1: npub stubs only. `ContactSummary.display_name` and `picture_url` are
 * currently always `null` from the kernel's `FollowListObserver` — profile
 * hydration (kind:0 metadata fetch) is deferred to slice 2. The short-npub
 * fallback label (first 8 + … + last 8 chars) matches the iOS
 * `NostrNpub.shortNpub` pattern used by the conversations screen.
 *
 * Empty states:
 *  - Signed-out (`snapshot == null` or `activeAccount == null`) — shows a
 *    "Sign in to see your following list" prompt.
 *  - Signed-in but zero follows — shows "No accounts followed yet."
 *
 * The kernel already maintains this projection reactively via
 * `FollowListObserver` (kind:3 events); no polling is required on Android.
 * The follow list rides the same `podcast.social` domain frame as
 * `nostrConversations` (atomic co-emit, same rev gate).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowingScreen(
    snapshot: PodcastSnapshot?,
    bridge: KernelBridge,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isSignedIn = snapshot?.activeAccount != null
    val following = snapshot?.following ?: emptyList()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    val count = following.size
                    Text(if (count > 0) "Following ($count)" else "Following")
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
        modifier = modifier,
    ) { inner ->
        when {
            !isSignedIn -> SignedOutEmptyState(Modifier.fillMaxSize().padding(inner))
            following.isEmpty() -> ZeroFollowsEmptyState(Modifier.fillMaxSize().padding(inner))
            else -> FollowingList(
                following = following,
                modifier = Modifier.fillMaxSize().padding(inner),
            )
        }
    }
}

@Composable
private fun FollowingList(
    following: List<ContactSummaryDto>,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier) {
        items(following, key = { it.npub }) { contact ->
            ContactRow(contact = contact)
            HorizontalDivider()
        }
    }
}

@Composable
private fun ContactRow(contact: ContactSummaryDto) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.Person,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(modifier = Modifier.weight(1f)) {
            val label = contact.displayName?.takeIf { it.isNotBlank() }
                ?: shortNpubLabel(contact.npub)
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (contact.displayName != null) {
                Text(
                    text = shortNpubLabel(contact.npub),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun SignedOutEmptyState(modifier: Modifier = Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = "Sign in to see your following list.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ZeroFollowsEmptyState(modifier: Modifier = Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = "No accounts followed yet.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Produces a short representation of a bech32 npub for display.
 *
 * For an npub like "npub1abc...xyz" produces "npub1abc…xyz" showing the first
 * 12 and last 8 characters, matching the iOS `NostrNpub.shortNpub` pattern.
 * Falls back to the raw string if it is too short to truncate.
 *
 * Named `shortNpubLabel` to avoid a package-level name collision with the
 * hex-variant `shortNpub` in `NostrConversationsScreen.kt`.
 */
private fun shortNpubLabel(npub: String): String {
    if (npub.length <= 20) return npub
    return "${npub.take(12)}…${npub.takeLast(8)}"
}
