package io.f7z.podcast.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import io.f7z.podcast.KernelBridge
import io.f7z.podcast.SocialActions

/**
 * Overflow menu for conversation-level trust actions, placed in the
 * [NostrConversationDetailScreen] TopAppBar.
 *
 * Surfaces Approve / Remove-Approval / Block for the conversation's
 * counterparty, wired into the kernel's `podcast.social` namespace via
 * [SocialActions].
 *
 * Trust semantics (kernel-owned, from `social_module.rs`):
 *
 *   trust(pubkey) = (followed || approved) && !blocked
 *
 * When [trusted] is false: "Approve" + "Block" are shown.
 * When [trusted] is true: "Remove Approval" + "Block" are shown.
 * Block is always available and requires a confirmation dialog.
 *
 * **REACTIVE contract**: this composable NEVER mutates the [trusted] flag
 * locally. It dispatches commands and lets the kernel push an updated
 * `NostrConversationDto.trusted` on the next snapshot frame, which flows
 * through the reactive push seam and recomposes this menu automatically.
 * No polling, no optimistic state (android_reactive_path_and_datadir).
 */
@Composable
fun NostrConversationTrustMenu(
    counterpartyHex: String,
    trusted: Boolean,
    bridge: KernelBridge,
) {
    var showMenu by remember { mutableStateOf(false) }
    var showBlockConfirm by remember { mutableStateOf(false) }

    IconButton(onClick = { showMenu = true }) {
        Icon(
            imageVector = Icons.Default.MoreVert,
            contentDescription = "Trust actions",
        )
    }

    DropdownMenu(
        expanded = showMenu,
        onDismissRequest = { showMenu = false },
    ) {
        if (!trusted) {
            DropdownMenuItem(
                text = { Text("Approve") },
                onClick = {
                    SocialActions.approvePeer(bridge, counterpartyHex)
                    showMenu = false
                },
            )
        } else {
            DropdownMenuItem(
                text = { Text("Remove Approval") },
                onClick = {
                    SocialActions.removeApproval(bridge, counterpartyHex)
                    showMenu = false
                },
            )
        }
        DropdownMenuItem(
            text = { Text("Block") },
            onClick = {
                showMenu = false
                showBlockConfirm = true
            },
        )
    }

    if (showBlockConfirm) {
        AlertDialog(
            onDismissRequest = { showBlockConfirm = false },
            title = { Text("Block this peer?") },
            text = {
                Text(
                    "This peer will be blocked from contacting your agent. " +
                        "Block overrides follow status and explicit approval. " +
                        "You can unblock from Settings → Access Control.",
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        SocialActions.blockPeer(bridge, counterpartyHex)
                        showBlockConfirm = false
                    },
                ) {
                    Text("Block")
                }
            },
            dismissButton = {
                TextButton(onClick = { showBlockConfirm = false }) {
                    Text("Cancel")
                }
            },
        )
    }
}
