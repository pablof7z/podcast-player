package io.f7z.podcast

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [ClipActions] wire-payload builders.
 *
 * Asserts the exact JSON shapes expected by
 * `apps/nmp-app-podcast/src/ffi/actions/clip_module.rs::ClipAction`:
 *
 * ```rust
 * #[serde(tag = "op", rename_all = "snake_case")]
 * pub enum ClipAction {
 *     Create { episode_id: String, start_secs: f64, end_secs: f64,
 *              #[serde(default, skip_serializing_if = "Option::is_none")]
 *              title: Option<String> },
 *     Delete { clip_id: String },
 *     AutoSnip { episode_id: String, position_secs: f64 },
 * }
 * ```
 *
 * All tests are pure-Kotlin (no Android runtime, no KernelBridge).
 */
class ClipActionsTest {

    private val json = Json { ignoreUnknownKeys = true }

    // ── create payload ────────────────────────────────────────────────────────

    @Test
    fun `buildCreatePayload op field is 'create'`() {
        val payload = ClipActions.buildCreatePayload(
            episodeId  = "ep-uuid-1",
            startSecs  = 10.0,
            endSecs    = 40.0,
        )
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals(
            "op must be 'create' (Rust ClipAction::Create rename_all=snake_case)",
            "create",
            obj["op"]?.jsonPrimitive?.content,
        )
    }

    @Test
    fun `buildCreatePayload encodes episode_id snake_case`() {
        val payload = ClipActions.buildCreatePayload("ep-abc", 0.0, 30.0)
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals(
            "episode_id must be snake_case (Rust ClipAction::Create field name)",
            "ep-abc",
            obj["episode_id"]?.jsonPrimitive?.content,
        )
    }

    @Test
    fun `buildCreatePayload encodes start_secs and end_secs as numbers`() {
        val payload = ClipActions.buildCreatePayload("ep-x", 15.5, 45.25)
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals(15.5, obj["start_secs"]?.jsonPrimitive?.double ?: -1.0, 0.001)
        assertEquals(45.25, obj["end_secs"]?.jsonPrimitive?.double ?: -1.0, 0.001)
    }

    @Test
    fun `buildCreatePayload omits title when null`() {
        val payload = ClipActions.buildCreatePayload("ep-x", 0.0, 10.0, title = null)
        val obj = json.parseToJsonElement(payload).jsonObject
        assertNull(
            "title must be absent from wire when null (Rust skip_serializing_if=Option::is_none)",
            obj["title"],
        )
    }

    @Test
    fun `buildCreatePayload omits title when blank`() {
        val payload = ClipActions.buildCreatePayload("ep-x", 0.0, 10.0, title = "   ")
        val obj = json.parseToJsonElement(payload).jsonObject
        assertNull(
            "title must be absent from wire when blank — empty string would write wrong kind:0",
            obj["title"],
        )
    }

    @Test
    fun `buildCreatePayload includes title when non-blank`() {
        val payload = ClipActions.buildCreatePayload("ep-x", 0.0, 10.0, title = "Marcus on retrieval")
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals(
            "title must be present in wire when non-blank",
            "Marcus on retrieval",
            obj["title"]?.jsonPrimitive?.content,
        )
    }

    @Test
    fun `buildCreatePayload trims title whitespace`() {
        val payload = ClipActions.buildCreatePayload("ep-x", 0.0, 10.0, title = "  trimmed  ")
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals("trimmed", obj["title"]?.jsonPrimitive?.content)
    }

    @Test
    fun `buildCreatePayload produces valid JSON`() {
        val payload = ClipActions.buildCreatePayload("ep-uuid", 60.0, 90.0, "Key moment")
        // Must not throw — valid JSON is the contract.
        val parsed = json.parseToJsonElement(payload)
        assertTrue("payload must decode as a JSON object", parsed is JsonObject)
    }

    // ── delete payload ────────────────────────────────────────────────────────

    @Test
    fun `buildDeletePayload op field is 'delete'`() {
        val payload = ClipActions.buildDeletePayload("clip-uuid-1")
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals(
            "op must be 'delete' (Rust ClipAction::Delete rename_all=snake_case)",
            "delete",
            obj["op"]?.jsonPrimitive?.content,
        )
    }

    @Test
    fun `buildDeletePayload encodes clip_id snake_case`() {
        val payload = ClipActions.buildDeletePayload("clip-abc-123")
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals(
            "clip_id must be snake_case (Rust ClipAction::Delete field name)",
            "clip-abc-123",
            obj["clip_id"]?.jsonPrimitive?.content,
        )
    }

    @Test
    fun `buildDeletePayload does not include episode_id or start_secs`() {
        val payload = ClipActions.buildDeletePayload("clip-x")
        val obj = json.parseToJsonElement(payload).jsonObject
        assertNull("episode_id must not be present in delete payload", obj["episode_id"])
        assertNull("start_secs must not be present in delete payload", obj["start_secs"])
    }

    // ── auto_snip payload ─────────────────────────────────────────────────────

    @Test
    fun `buildAutoSnipPayload op field is 'auto_snip'`() {
        val payload = ClipActions.buildAutoSnipPayload("ep-uuid", 120.0)
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals(
            "op must be 'auto_snip' (Rust ClipAction::AutoSnip rename_all=snake_case)",
            "auto_snip",
            obj["op"]?.jsonPrimitive?.content,
        )
    }

    @Test
    fun `buildAutoSnipPayload encodes episode_id and position_secs`() {
        val payload = ClipActions.buildAutoSnipPayload("ep-yyy", 300.5)
        val obj = json.parseToJsonElement(payload).jsonObject
        assertEquals("ep-yyy", obj["episode_id"]?.jsonPrimitive?.content)
        assertEquals(300.5, obj["position_secs"]?.jsonPrimitive?.double ?: -1.0, 0.001)
    }

    // ── NAMESPACE constant ────────────────────────────────────────────────────

    @Test
    fun `NAMESPACE constant matches Rust ClipActionModule NAMESPACE`() {
        assertEquals(
            "NAMESPACE must match Rust ClipActionModule::NAMESPACE = \"podcast.clip\"",
            "podcast.clip",
            ClipActions.NAMESPACE,
        )
    }
}
