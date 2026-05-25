package io.f7z.podcast

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Single-Activity Compose host for the M2.F proof-of-concept.
 *
 * The screen shows three things the milestone exit checklist calls for:
 *
 *  1. A status line ("Kernel running" / "Kernel idle") derived from
 *     `KernelBridge.isAlive()` — proves the actor came up.
 *  2. A `LazyColumn` listing whatever subscriptions the Rust snapshot
 *     emits. Today the payload is a stub; once M2.A's `LibraryProjection`
 *     is serialized, the same UI will start rendering real shows with
 *     zero Kotlin-side changes.
 *  3. A "Sign in (stub)" button that dispatches one capability call via
 *     the same `KernelBridge` Swift uses — the milestone's "one capability
 *     hop on the second platform" gate.
 *
 * No business logic lives in Kotlin (D0). Everything decoded from the
 * snapshot is computed by Rust.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                PodcastRoot()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PodcastRoot() {
    // Hold the bridge for the lifetime of this composition. `DisposableEffect`
    // tears it down when the composition leaves the tree — mirror of iOS's
    // `PodcastHandle.deinit` chain.
    val bridge = remember { KernelBridge() }
    var snapshot by remember { mutableStateOf<PodcastSnapshot?>(null) }
    var status by remember { mutableStateOf("starting…") }

    DisposableEffect(bridge) {
        bridge.start()
        onDispose {
            bridge.stop()
            bridge.free()
        }
    }

    // Cheap polling loop: refresh the projection every ~500 ms. A production
    // build would drive this off `nextUpdate()` on an I/O coroutine — that
    // path also works today and is left as M3 polish.
    LaunchedEffect(bridge) {
        while (true) {
            val raw = withContext(Dispatchers.IO) { bridge.podcastSnapshot() }
            snapshot = SnapshotCodec.decode(raw)
            status = if (bridge.isAlive()) "Kernel running" else "Kernel idle"
            delay(500)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Podcast — M2.F proof") })
        },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            StatusCard(status, snapshot)
            SignInButton(bridge)
            LibraryList(snapshot)
        }
    }
}

@Composable
private fun StatusCard(status: String, snapshot: PodcastSnapshot?) {
    Card {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(text = status, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                text = "rev: ${snapshot?.rev ?: "-"}  schema: ${snapshot?.schemaVersion ?: "-"}",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun SignInButton(bridge: KernelBridge) {
    Button(onClick = {
        // Stub nsec — the milestone calls for *one* dispatch round trip on
        // the second platform, not a working sign-in. The kernel will reject
        // this and the rejection envelope will arrive on the next snapshot.
        bridge.signinNsec("nsec1stubvaluefortheproofofconcept0000000000000000000000000000000000")
    }) {
        Text("Sign in (stub)")
    }
}

@Composable
private fun LibraryList(snapshot: PodcastSnapshot?) {
    val rows = snapshot?.library.orEmpty()
    if (rows.isEmpty()) {
        Text(
            text = "No subscriptions yet. (M2.A wires the LibraryProjection; this list will fill in once the Rust snapshot exposes it.)",
            style = MaterialTheme.typography.bodyMedium,
        )
        return
    }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items(rows, key = { it.id }) { row ->
            Card {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(row.title, style = MaterialTheme.typography.titleSmall)
                    Text(
                        "${row.episodeCount} episodes • ${row.unplayedCount} unplayed",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}
