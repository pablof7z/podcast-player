package io.f7z.podcast

import androidx.media3.common.Player
import io.f7z.podcast.capabilities.KernelForwardingPlayer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.junit.Assert.assertEquals

/**
 * Unit tests for [KernelForwardingPlayer] transport routing.
 *
 * Verifies that when a [KernelDispatcher] is set, media3 transport commands
 * (play/pause/seekTo/seekForward/seekBack) dispatch to the kernel instead of
 * executing directly on the inner player. With bridge = null, commands fall
 * back to the inner player.
 *
 * Uses Mockito to stub the media3 [Player] interface (many abstract methods;
 * a manual full implementation would be brittle). Uses [FakeDispatcher] (not
 * [KernelBridge]) as the bridge double — [KernelBridge]'s init block loads
 * the native `.so` via System.loadLibrary, which is unavailable in JVM tests.
 */
class MediaSessionTransportRoutingTest {

    private val json = Json

    // MARK: - Bridge routing tests

    @Test
    fun playWithBridgeDispatchesResume() {
        val forwarder = KernelForwardingPlayer(mock(Player::class.java))
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.play()

        assertEquals(1, dispatcher.actions.size)
        val payload = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals("podcast.player", dispatcher.actions[0].namespace)
        assertEquals("resume", payload["op"]?.jsonPrimitive?.content)
    }

    @Test
    fun pauseWithBridgeDispatchesPause() {
        val forwarder = KernelForwardingPlayer(mock(Player::class.java))
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.pause()

        assertEquals(1, dispatcher.actions.size)
        val payload = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals("pause", payload["op"]?.jsonPrimitive?.content)
    }

    @Test
    fun seekToWithBridgeDispatchesSeek() {
        val forwarder = KernelForwardingPlayer(mock(Player::class.java))
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.seekTo(0, 90_000L) // 90 seconds in milliseconds

        assertEquals(1, dispatcher.actions.size)
        val payload = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals("seek", payload["op"]?.jsonPrimitive?.content)
        assertEquals(90.0, payload["position_secs"]?.jsonPrimitive?.content?.toDouble())
    }

    @Test
    fun seekForwardWithBridgeDispatchesAbsoluteSeek() {
        val innerPlayer = mock(Player::class.java)
        `when`(innerPlayer.currentPosition).thenReturn(60_000L)
        `when`(innerPlayer.seekForwardIncrementMs).thenReturn(15_000L)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.seekForward()

        // seekForward now dispatches a single absolute seek (base + increment),
        // not a position-sync + skip pair. This ensures consecutive paused taps
        // accumulate correctly without re-anchoring to the stale ExoPlayer position.
        assertEquals(1, dispatcher.actions.size)
        val payload = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals("seek", payload["op"]?.jsonPrimitive?.content)
        assertEquals(75.0, payload["position_secs"]?.jsonPrimitive?.content?.toDouble())
    }

    @Test
    fun seekForwardAccumulatesAcrossConsecutivePausedTaps() {
        val innerPlayer = mock(Player::class.java)
        `when`(innerPlayer.currentPosition).thenReturn(60_000L)
        `when`(innerPlayer.seekForwardIncrementMs).thenReturn(15_000L)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.seekForward() // base=60s, target=75s
        forwarder.seekForward() // base=75s (pending), target=90s

        assertEquals(2, dispatcher.actions.size)
        val p1 = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals(75.0, p1["position_secs"]?.jsonPrimitive?.content?.toDouble())
        val p2 = json.parseToJsonElement(dispatcher.actions[1].payload).jsonObject
        assertEquals(90.0, p2["position_secs"]?.jsonPrimitive?.content?.toDouble())
    }

    @Test
    fun seekBackWithBridgeDispatchesAbsoluteSeek() {
        val innerPlayer = mock(Player::class.java)
        `when`(innerPlayer.currentPosition).thenReturn(60_000L)
        `when`(innerPlayer.seekBackIncrementMs).thenReturn(15_000L)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.seekBack()

        // seekBack now dispatches a single absolute seek (base - increment),
        // matching the accumulation fix applied to seekForward.
        assertEquals(1, dispatcher.actions.size)
        val payload = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals("seek", payload["op"]?.jsonPrimitive?.content)
        assertEquals(45.0, payload["position_secs"]?.jsonPrimitive?.content?.toDouble())
    }

    @Test
    fun seekBackAccumulatesAcrossConsecutivePausedTaps() {
        val innerPlayer = mock(Player::class.java)
        `when`(innerPlayer.currentPosition).thenReturn(60_000L)
        `when`(innerPlayer.seekBackIncrementMs).thenReturn(15_000L)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.seekBack() // base=60s, target=45s
        forwarder.seekBack() // base=45s (pending), target=30s

        assertEquals(2, dispatcher.actions.size)
        val p1 = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals(45.0, p1["position_secs"]?.jsonPrimitive?.content?.toDouble())
        val p2 = json.parseToJsonElement(dispatcher.actions[1].payload).jsonObject
        assertEquals(30.0, p2["position_secs"]?.jsonPrimitive?.content?.toDouble())
    }

    @Test
    fun playWithBridgeClearsPendingPausedSeekBase() {
        val innerPlayer = mock(Player::class.java)
        `when`(innerPlayer.currentPosition).thenReturn(60_000L)
        `when`(innerPlayer.seekForwardIncrementMs).thenReturn(15_000L)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        val dispatcher = FakeDispatcher()
        forwarder.bridge = dispatcher

        forwarder.seekForward() // pending=75s
        forwarder.play()        // should clear pending; dispatches resume
        dispatcher.actions.clear()

        // After play() clears the pending base, the next seekForward should
        // re-anchor to currentPosition (60s) rather than the stale pending (75s).
        // With increment=15s: 60+15=75s (same value, but anchored to live pos).
        forwarder.seekForward()
        assertEquals(1, dispatcher.actions.size)
        val payload = json.parseToJsonElement(dispatcher.actions[0].payload).jsonObject
        assertEquals("seek", payload["op"]?.jsonPrimitive?.content)
        assertEquals(75.0, payload["position_secs"]?.jsonPrimitive?.content?.toDouble())
    }

    // MARK: - Fallback tests (bridge = null)

    @Test
    fun playWithoutBridgeFallsBackToInnerPlayer() {
        val innerPlayer = mock(Player::class.java)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        // bridge = null (default)

        forwarder.play()

        verify(innerPlayer).play()
    }

    @Test
    fun pauseWithoutBridgeFallsBackToInnerPlayer() {
        val innerPlayer = mock(Player::class.java)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        // bridge = null

        forwarder.pause()

        verify(innerPlayer).pause()
    }

    @Test
    fun seekToWithoutBridgeFallsBackToInnerPlayer() {
        val innerPlayer = mock(Player::class.java)
        val forwarder = KernelForwardingPlayer(innerPlayer)
        // bridge = null

        forwarder.seekTo(0, 60_000L) // 60 seconds

        verify(innerPlayer).seekTo(0, 60_000L)
    }
}

// MARK: - Fakes

private data class DispatchedAction(
    val namespace: String,
    val payload: String,
)

/**
 * Fake [KernelDispatcher] for testing that records dispatch calls.
 *
 * Implements [KernelDispatcher] (the thin interface extracted for testability),
 * NOT [KernelBridge] (which loads a native .so in its init block).
 */
private class FakeDispatcher : KernelDispatcher {
    val actions = mutableListOf<DispatchedAction>()

    override fun dispatchAction(namespace: String, payloadJson: String): String? {
        actions.add(DispatchedAction(namespace, payloadJson))
        return null
    }
}
