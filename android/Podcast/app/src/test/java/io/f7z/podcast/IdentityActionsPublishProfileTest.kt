package io.f7z.podcast

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [IdentityActions.buildPublishProfilePayload].
 *
 * Verifies the JSON wire shape against the Rust kernel handler contract
 * (`ffi/actions/social_module.rs` `SocialAction::PublishProfile`):
 *
 * ```rust
 * #[serde(tag = "op", rename_all = "snake_case")]
 * pub enum SocialAction {
 *     PublishProfile {
 *         name: String,
 *         #[serde(default, skip_serializing_if = "Option::is_none")]
 *         display_name: Option<String>,
 *         #[serde(default, skip_serializing_if = "Option::is_none")]
 *         about: Option<String>,
 *         #[serde(default, skip_serializing_if = "Option::is_none")]
 *         picture: Option<String>,
 *     },
 * }
 * ```
 *
 * The `op` value must be `"publish_profile"` (snake_case of the variant name).
 * Optional fields must be OMITTED (not null/empty) when blank, because the kernel
 * uses `skip_serializing_if = "Option::is_none"` — the kernel deserializer uses
 * `#[serde(default)]` which defaults absent fields to `None`, so omitting them is
 * equivalent to `None`. Sending `"display_name":""` would be a non-None string,
 * potentially writing an empty display_name to the kind:0 content.
 *
 * Reference: `UserIdentityStore+Publishing.swift` dispatches the same payload as:
 * ```swift
 * dispatchToKernel(namespace: "podcast.social", body: [
 *     "op": "publish_profile",
 *     "name": name,
 *     "display_name": displayName,
 *     "about": about,
 *     "picture": picture,
 * ])
 * ```
 */
class IdentityActionsPublishProfileTest {

    private val json = Json

    private fun parse(payload: String): JsonObject =
        json.decodeFromString(JsonObject.serializer(), payload)

    // ── op discriminator ──────────────────────────────────────────────────────

    @Test
    fun `op field is publish_profile snake_case`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "alice",
                displayName = "Alice",
                about = "",
                pictureUrl = "",
            )
        )
        assertEquals("publish_profile", obj["op"]?.jsonPrimitive?.content)
    }

    // ── required name field ───────────────────────────────────────────────────

    @Test
    fun `name field is included and trimmed`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "  alice  ",
                displayName = "",
                about = "",
                pictureUrl = "",
            )
        )
        assertEquals("alice", obj["name"]?.jsonPrimitive?.content)
    }

    @Test
    fun `empty name is preserved as empty string`() {
        // name is required (String, not Option<String>) — always emitted.
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "",
                displayName = "",
                about = "",
                pictureUrl = "",
            )
        )
        assertTrue("name key must always be present", obj.containsKey("name"))
        assertEquals("", obj["name"]?.jsonPrimitive?.content)
    }

    // ── optional fields omitted when blank ────────────────────────────────────

    @Test
    fun `blank display_name is omitted from payload`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "alice",
                displayName = "",
                about = "",
                pictureUrl = "",
            )
        )
        assertFalse(
            "display_name must be absent when blank — kernel uses Option<String>",
            obj.containsKey("display_name"),
        )
    }

    @Test
    fun `blank about is omitted from payload`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "alice",
                displayName = "Alice",
                about = "",
                pictureUrl = "",
            )
        )
        assertFalse(
            "about must be absent when blank — kernel uses Option<String>",
            obj.containsKey("about"),
        )
    }

    @Test
    fun `blank picture is omitted from payload`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "alice",
                displayName = "Alice",
                about = "Podcaster",
                pictureUrl = "",
            )
        )
        assertFalse(
            "picture must be absent when blank — kernel uses Option<String>",
            obj.containsKey("picture"),
        )
    }

    @Test
    fun `whitespace-only optional fields are omitted`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "alice",
                displayName = "   ",
                about = "\t",
                pictureUrl = "  ",
            )
        )
        assertFalse(obj.containsKey("display_name"))
        assertFalse(obj.containsKey("about"))
        assertFalse(obj.containsKey("picture"))
    }

    // ── optional fields present when non-blank ────────────────────────────────

    @Test
    fun `non-blank optional fields are included and trimmed`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "alice",
                displayName = "  Alice Smith  ",
                about = "  Podcaster  ",
                pictureUrl = "  https://example.com/pic.jpg  ",
            )
        )
        assertEquals("Alice Smith", obj["display_name"]?.jsonPrimitive?.content)
        assertEquals("Podcaster", obj["about"]?.jsonPrimitive?.content)
        assertEquals("https://example.com/pic.jpg", obj["picture"]?.jsonPrimitive?.content)
    }

    // ── full round-trip shape ─────────────────────────────────────────────────

    @Test
    fun `full payload contains exactly op name display_name about picture`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "bright-signal",
                displayName = "Bright Signal",
                about = "A podcast about software.",
                pictureUrl = "https://cdn.example.com/avatar.png",
            )
        )
        assertEquals("publish_profile", obj["op"]?.jsonPrimitive?.content)
        assertEquals("bright-signal", obj["name"]?.jsonPrimitive?.content)
        assertEquals("Bright Signal", obj["display_name"]?.jsonPrimitive?.content)
        assertEquals("A podcast about software.", obj["about"]?.jsonPrimitive?.content)
        assertEquals("https://cdn.example.com/avatar.png", obj["picture"]?.jsonPrimitive?.content)
        // No unexpected extra keys beyond the 5 above.
        assertEquals("Unexpected extra keys in payload", 5, obj.size)
    }

    @Test
    fun `minimal payload contains only op and name`() {
        val obj = parse(
            IdentityActions.buildPublishProfilePayload(
                name = "alice",
                displayName = "",
                about = "",
                pictureUrl = "",
            )
        )
        assertEquals(2, obj.size)
        assertTrue(obj.containsKey("op"))
        assertTrue(obj.containsKey("name"))
    }
}
