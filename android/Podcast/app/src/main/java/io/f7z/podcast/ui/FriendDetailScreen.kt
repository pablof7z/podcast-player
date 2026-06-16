package io.f7z.podcast.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.f7z.podcast.KernelBridge
import io.f7z.podcast.PodcastSnapshot

/**
 * Friend Detail screen — tapping a row in [FollowingScreen] opens this surface
 * (Android social parity, slice 4).
 *
 * Displays the contact's resolved profile: large [NostrAvatar], display name,
 * copyable npub, and copyable hex pubkey. [ResolvedProfile] only carries
 * `display` + `pictureUrl` — richer fields (about, nip05, banner) would require
 * a kernel projection extension and are intentionally out of scope.
 *
 * Profile hydration is fully reactive: on appear the screen calls
 * `bridge.claimProfile(pubkeyHex, "FriendDetail")` so the kernel fetches the
 * contact's kind:0 metadata and delivers it in
 * `snapshot.resolvedProfiles[pubkeyHex]`. The claim is released on dispose via
 * [DisposableEffect], mirroring [NostrConversationDetailScreen] exactly.
 *
 * Guard: an empty [pubkeyHex] skips the claim to avoid leaking a refcount on
 * the sentinel entry in the kernel's resolved-profiles map.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FriendDetailScreen(
    pubkeyHex: String,
    npub: String,
    snapshot: PodcastSnapshot?,
    bridge: KernelBridge,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val resolvedProfile = snapshot?.resolvedProfiles?.get(pubkeyHex)
    val displayName = resolvedProfile?.display?.takeIf { it.isNotBlank() }
        ?: shortNpubLabel(npub)

    // Claim the contact's pubkey so the kernel resolves kind:0 profile metadata
    // and delivers it in projections["resolved_profiles"]. Consumer ID is stable
    // for this screen — only one FriendDetail is ever shown at a time; the kernel
    // dedupes across re-entries. Released on dispose (mirrors
    // NostrConversationDetailScreen.DisposableEffect).
    val consumerID = "FriendDetail"
    DisposableEffect(pubkeyHex) {
        if (pubkeyHex.isNotEmpty()) {
            bridge.claimProfile(pubkeyHex, consumerID)
        }
        onDispose {
            if (pubkeyHex.isNotEmpty()) {
                bridge.releaseProfile(pubkeyHex, consumerID)
            }
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = displayName,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
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
    ) { innerPadding ->
        FriendDetailContent(
            pubkeyHex = pubkeyHex,
            npub = npub,
            displayName = displayName,
            pictureUrl = resolvedProfile?.pictureUrl,
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        )
    }
}

@Composable
private fun FriendDetailContent(
    pubkeyHex: String,
    npub: String,
    displayName: String,
    pictureUrl: String?,
    modifier: Modifier = Modifier,
) {
    val clipboard = LocalClipboardManager.current

    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Top,
    ) {
        // Large avatar — 80 dp matches iOS NostrAvatarView large variant.
        NostrAvatar(
            pictureUrl = pictureUrl,
            modifier = Modifier.size(80.dp),
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Display name — prominently sized, centered below the avatar.
        Text(
            text = displayName,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(28.dp))

        // npub (bech32) — selectable for long-press copy; explicit copy button
        // for discoverability (matches iOS TextSelection + copy button pattern).
        CopyableIdentityField(
            label = "npub",
            value = npub,
            onCopy = { clipboard.setText(AnnotatedString(npub)) },
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Raw hex pubkey — useful for Nostr tooling and relays.
        CopyableIdentityField(
            label = "Hex pubkey",
            value = pubkeyHex,
            onCopy = { clipboard.setText(AnnotatedString(pubkeyHex)) },
        )
    }
}

/**
 * A card row displaying a labelled identity string with a copy-to-clipboard
 * icon button. Consistent with the M3 list-item style used throughout the app.
 */
@Composable
private fun CopyableIdentityField(
    label: String,
    value: String,
    onCopy: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = value,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(onClick = onCopy) {
                Icon(
                    imageVector = Icons.Filled.ContentCopy,
                    contentDescription = "Copy $label",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}
