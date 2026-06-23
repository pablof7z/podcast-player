package io.f7z.podcast

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.test.utils.FakePlayer
import io.f7z.podcast.capabilities.KernelForwardingPlayer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Unit tests for [KernelForwardingPlayer] transport routing.
 *
 * Verifies that when a `KernelBridge` is set, media3 transport commands
 * (play/pause/seekTo/seekForward/seekBack) dispatch to the kernel instead
 * of executing directly on the inner player. With bridge = null, commands
 * fall back to the inner player (no crash).
 */
class MediaSessionTransportRoutingTest {

    private val json = Json

    // MARK: - Tests

    @Test
    fun playWithBridgeDispatchesResume() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        val bridge = FakeBridge()
        forwarder.bridge = bridge

        forwarder.play()

        assertEquals(1, bridge.dispatchedActions.size)
        val action = bridge.dispatchedActions[0]
        assertEquals("podcast.player", action.namespace)

        val payload = json.parseToJsonElement(action.payload).jsonObject
        assertEquals("resume", payload["op"]?.jsonPrimitive?.content)
    }

    @Test
    fun pauseWithBridgeDispatchesPause() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        val bridge = FakeBridge()
        forwarder.bridge = bridge

        forwarder.pause()

        assertEquals(1, bridge.dispatchedActions.size)
        val action = bridge.dispatchedActions[0]
        assertEquals("pause", json.parseToJsonElement(action.payload).jsonObject["op"]?.jsonPrimitive?.content)
    }

    @Test
    fun seekToWithBridgeDispatchesSeek() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        val bridge = FakeBridge()
        forwarder.bridge = bridge

        forwarder.seekTo(0, 90_000L) // 90 seconds in milliseconds

        assertEquals(1, bridge.dispatchedActions.size)
        val action = bridge.dispatchedActions[0]
        val payload = json.parseToJsonElement(action.payload).jsonObject
        assertEquals("seek", payload["op"]?.jsonPrimitive?.content)
        assertEquals(90.0, payload["position_secs"]?.jsonPrimitive?.content?.toDouble())
    }

    @Test
    fun seekForwardWithBridgeDispatchesSkipForward() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        val bridge = FakeBridge()
        forwarder.bridge = bridge

        forwarder.seekForward()

        assertEquals(1, bridge.dispatchedActions.size)
        val action = bridge.dispatchedActions[0]
        val payload = json.parseToJsonElement(action.payload).jsonObject
        assertEquals("skip_forward", payload["op"]?.jsonPrimitive?.content)
    }

    @Test
    fun seekBackWithBridgeDispatchesSkipBackward() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        val bridge = FakeBridge()
        forwarder.bridge = bridge

        forwarder.seekBack()

        assertEquals(1, bridge.dispatchedActions.size)
        val action = bridge.dispatchedActions[0]
        val payload = json.parseToJsonElement(action.payload).jsonObject
        assertEquals("skip_backward", payload["op"]?.jsonPrimitive?.content)
    }

    @Test
    fun playWithoutBridgeFallsBackToInnerPlayer() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        // bridge = null (default)

        forwarder.play()

        assertEquals(true, fakePlayer.playWhenReady)
    }

    @Test
    fun pauseWithoutBridgeFallsBackToInnerPlayer() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        fakePlayer.playWhenReady = true
        // bridge = null

        forwarder.pause()

        assertEquals(false, fakePlayer.playWhenReady)
    }

    @Test
    fun seekToWithoutBridgeFallsBackToInnerPlayer() {
        val fakePlayer = FakePlayer()
        val forwarder = KernelForwardingPlayer(fakePlayer)
        fakePlayer.setMediaItem(MediaItem.fromUri("https://example.com/audio.mp3"))
        // bridge = null

        forwarder.seekTo(0, 60_000L) // 60 seconds

        assertEquals(60_000L, fakePlayer.currentPosition)
    }
}

// MARK: - Fakes

private data class DispatchedAction(
    val namespace: String,
    val payload: String,
)

/**
 * Fake [KernelBridge] for testing that records dispatch calls.
 */
private class FakeBridge : KernelBridge {
    val dispatchedActions = mutableListOf<DispatchedAction>()

    override fun dispatchAction(namespace: String, payload: String): String? {
        dispatchedActions.add(DispatchedAction(namespace, payload))
        return null
    }

    override fun capabilityReport(namespace: String, payload: String): String? = null
    override fun authorizationRequest(body: String): String? = null
}
