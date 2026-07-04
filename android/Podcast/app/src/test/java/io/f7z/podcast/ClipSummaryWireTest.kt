package io.f7z.podcast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Wire-fixture tests for `ClipSummary` and the `podcast.misc` clips projection
 * decode path.
 *
 * Mirrors the [DomainFrameWireTest] pattern: JSON fixtures are Rust-shaped
 * (snake_case field names exactly as `nmp_app_podcast_decode_update_frame`
 * emits them in the `podcast.misc` sidecar under `clips`).
 *
 * Contract under test (wire shape verified against
 * `apps/nmp-app-podcast/src/ffi/projections/clips.rs::ClipSummary`):
 *
 * ```json
 * {
 *   "id": "<uuid>",
 *   "episode_id": "<uuid>",
 *   "episode_title": "…",
 *   "podcast_title": "…",
 *   "start_secs": N,
 *   "end_secs": N,
 *   "title": "…",          // optional — absent when user did not name the clip
 *   "created_at": N        // Unix seconds
 * }
 * ```
 *
 * Tests:
 *  1. ClipSummary decodes snake_case wire keys → camelCase Kotlin fields.
 *  2. Optional `title` decodes as null when absent.
 *  3. `podcast.misc` frame with clips list decodes via SnapshotCodec.
 *  4. mergeFrames wires clips from MiscDomainFrame into PodcastSnapshot.clips.
 *  5. A misc frame without clips does NOT clear snapshot.clips (null = no change).
 */
class ClipSummaryWireTest {

    // ── Fixture helpers ───────────────────────────────────────────────────────

    private fun envelope(vararg pairs: Pair<String, String>): String {
        val projBody = pairs.joinToString(",") { (k, v) -> "\"$k\":$v" }
        return """{"t":"snapshot","v":{"rev":1,"running":true,"projections":{$projBody}}}"""
    }

    private val namedClipJson = """
        {
          "id": "clip-uuid-1",
          "episode_id": "ep-uuid-1",
          "episode_title": "How to Think About Keto",
          "podcast_title": "The Peter Attia Drive",
          "start_secs": 840.0,
          "end_secs": 898.0,
          "title": "Marcus on retrieval",
          "created_at": 1717200000
        }
    """.trimIndent()

    private val unnamedClipJson = """
        {
          "id": "clip-uuid-2",
          "episode_id": "ep-uuid-2",
          "episode_title": "Zone 2 Fundamentals",
          "podcast_title": "The Peter Attia Drive",
          "start_secs": 120.0,
          "end_secs": 150.0,
          "created_at": 1717200100
        }
    """.trimIndent()

    private val miscFrameWithClips = """
        {
          "rev": 20,
          "clips": [
            $namedClipJson,
            $unnamedClipJson
          ]
        }
    """.trimIndent()

    private val miscFrameNoClips = """
        {
          "rev": 21,
          "agent_tasks": []
        }
    """.trimIndent()

    private val miscFrameEmptyClips = """
        {
          "rev": 22,
          "clips": []
        }
    """.trimIndent()

    // ── 1. ClipSummary snake_case decode ──────────────────────────────────────

    @Test
    fun `ClipSummary decodes snake_case fields from misc frame`() {
        val raw = envelope("podcast.misc" to miscFrameWithClips)
        val frames = DomainFrameFixtures.decodeDomainFrames(raw)
        assertNotNull("misc frame must decode", frames)
        val misc = frames!!.misc
        assertNotNull("misc domain must be present", misc)

        val clips = misc!!.clips
        assertNotNull("clips must be present", clips)
        assertEquals(2, clips!!.size)

        val named = clips[0]
        assertEquals("clip-uuid-1", named.id)
        assertEquals("ep-uuid-1",   named.episodeId)      // episode_id → episodeId
        assertEquals("How to Think About Keto", named.episodeTitle) // episode_title
        assertEquals("The Peter Attia Drive",   named.podcastTitle) // podcast_title
        assertEquals(840.0, named.startSecs, 0.001)        // start_secs → startSecs
        assertEquals(898.0, named.endSecs,   0.001)        // end_secs   → endSecs
        assertEquals("Marcus on retrieval", named.title)
        assertEquals(1717200000L, named.createdAt)         // created_at → createdAt
    }

    // ── 2. Optional title absent → null ──────────────────────────────────────

    @Test
    fun `ClipSummary decodes null title when title absent from wire`() {
        val raw = envelope("podcast.misc" to miscFrameWithClips)
        val frames = DomainFrameFixtures.decodeDomainFrames(raw)
        val unnamed = frames!!.misc!!.clips!![1]

        assertEquals("clip-uuid-2",         unnamed.id)
        assertEquals("Zone 2 Fundamentals", unnamed.episodeTitle)
        assertEquals(120.0, unnamed.startSecs, 0.001)
        assertEquals(150.0, unnamed.endSecs,   0.001)
        assertNull(
            "title must be null when absent from wire (Rust skip_serializing_if=Option::is_none)",
            unnamed.title,
        )
        assertEquals(1717200100L, unnamed.createdAt)
    }

    // ── 3. DomainFrameFixtures.decodeDomainFrames decodes misc clips list ───────────

    @Test
    fun `decodeDomainFrames decodes misc clips list correctly`() {
        val raw = envelope("podcast.misc" to miscFrameWithClips)
        val frames = DomainFrameFixtures.decodeDomainFrames(raw)
        assertNotNull("frames must not be null", frames)
        assertNotNull("misc domain must be non-null", frames!!.misc)
        assertEquals(20L, frames.misc!!.rev)
        assertEquals(2, frames.misc!!.clips!!.size)
    }

    // ── 4. mergeFrames wires clips into PodcastSnapshot.clips ─────────────────

    @Test
    fun `mergeFrames populates PodcastSnapshot clips from misc frame`() {
        val raw = envelope("podcast.misc" to miscFrameWithClips)
        val frames = DomainFrameFixtures.decodeDomainFrames(raw)
        assertNotNull("frames must decode", frames)

        val tracker = DomainRevTracker()
        val (snap, accepted) = SnapshotCodec.mergeFrames(frames!!, PodcastSnapshot(), tracker)

        assertTrue("misc frame must be accepted", accepted)
        assertEquals("snapshot must have 2 clips after merge", 2, snap.clips.size)

        val first = snap.clips[0]
        assertEquals("clip-uuid-1", first.id)
        assertEquals("How to Think About Keto", first.episodeTitle)
        assertEquals(840.0, first.startSecs, 0.001)
        assertEquals("Marcus on retrieval", first.title)
        assertEquals(1717200000L, first.createdAt)

        val second = snap.clips[1]
        assertEquals("clip-uuid-2", second.id)
        assertNull("unnamed clip title must be null in snapshot", second.title)
    }

    // ── 5. misc frame without clips does NOT clear snapshot.clips ─────────────

    @Test
    fun `misc frame without clips key does not clear snapshot clips (null = no change)`() {
        // Seed: apply a misc frame with 2 clips.
        val seedRaw = envelope("podcast.misc" to miscFrameWithClips)
        val seedFrames = DomainFrameFixtures.decodeDomainFrames(seedRaw)!!
        val tracker = DomainRevTracker()
        val (seeded, _) = SnapshotCodec.mergeFrames(seedFrames, PodcastSnapshot(), tracker)
        assertEquals("seeded snapshot must have 2 clips", 2, seeded.clips.size)

        // Apply a misc frame that does NOT carry a 'clips' key (rev=21).
        // Per delta-merge: null clips in frame → retain prior clips in snapshot.
        val noClipsRaw = envelope("podcast.misc" to miscFrameNoClips)
        val noClipsFrames = DomainFrameFixtures.decodeDomainFrames(noClipsRaw)!!
        assertNull(
            "misc frame without clips key must decode clips as null",
            noClipsFrames.misc!!.clips,
        )

        val (afterNoClips, accepted) = SnapshotCodec.mergeFrames(noClipsFrames, seeded, tracker)
        assertTrue("misc frame must be accepted (rev=21 > rev=20)", accepted)
        assertEquals(
            "snapshot.clips must be retained when incoming frame has no clips key",
            2,
            afterNoClips.clips.size,
        )
    }

    // ── 6. Empty clips list from kernel clears snapshot.clips ─────────────────

    @Test
    fun `misc frame with empty clips list clears snapshot clips`() {
        // Seed: 2 clips.
        val seedRaw = envelope("podcast.misc" to miscFrameWithClips)
        val seedFrames = DomainFrameFixtures.decodeDomainFrames(seedRaw)!!
        val tracker = DomainRevTracker()
        val (seeded, _) = SnapshotCodec.mergeFrames(seedFrames, PodcastSnapshot(), tracker)
        assertEquals(2, seeded.clips.size)

        // Apply a misc frame with clips=[] (all clips deleted).
        val emptyClipsRaw = envelope("podcast.misc" to miscFrameEmptyClips)
        val emptyClipsFrames = DomainFrameFixtures.decodeDomainFrames(emptyClipsRaw)!!
        assertNotNull("clips must decode as empty list, not null", emptyClipsFrames.misc!!.clips)
        assertTrue("clips list must be empty", emptyClipsFrames.misc!!.clips!!.isEmpty())

        val (afterEmpty, accepted) = SnapshotCodec.mergeFrames(emptyClipsFrames, seeded, tracker)
        assertTrue("empty-clips frame must be accepted", accepted)
        assertTrue(
            "snapshot.clips must be cleared when kernel sends empty list",
            afterEmpty.clips.isEmpty(),
        )
    }

    // ── 7. Drop-guard prevents stale misc from overwriting clips ──────────────

    @Test
    fun `drop-guard ignores stale misc rev and preserves snapshot clips`() {
        // Seed: rev=20 misc frame with 2 clips.
        val seedRaw = envelope("podcast.misc" to miscFrameWithClips)  // rev=20
        val seedFrames = DomainFrameFixtures.decodeDomainFrames(seedRaw)!!
        val tracker = DomainRevTracker()
        val (seeded, _) = SnapshotCodec.mergeFrames(seedFrames, PodcastSnapshot(), tracker)
        assertEquals(20L, tracker.misc)
        assertEquals(2, seeded.clips.size)

        // Stale rev=5 frame with empty clips — must be dropped.
        val stale = """{"rev":5,"clips":[]}"""
        val staleFrames = DomainFrameFixtures.decodeDomainFrames(envelope("podcast.misc" to stale))!!
        val (afterStale, accepted) = SnapshotCodec.mergeFrames(staleFrames, seeded, tracker)
        assertFalse("stale-rev misc frame must be rejected by drop-guard", accepted)
        assertEquals("clips must be unchanged after stale-rev drop", 2, afterStale.clips.size)
        assertEquals("tracker must not advance on stale frame", 20L, tracker.misc)
    }
}
