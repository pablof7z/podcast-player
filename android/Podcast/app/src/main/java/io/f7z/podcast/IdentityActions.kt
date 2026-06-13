package io.f7z.podcast

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.Json

/**
 * Canonical wire contract for the `podcast.identity` kernel action namespace.
 *
 * **Why not `bridge.signinNsec`?** The `nativeSigninNsec` / `bridge.signinNsec`
 * path calls the kernel's `nmp_app_signin_nsec`, which feeds the *nmp-core*
 * multi-account store. The Android snapshot's `activeAccount` is built
 * elsewhere — from the podcast-app `IdentityStore` (`ffi/snapshot.rs`),
 * populated ONLY by the `podcast.identity` actions below. So sign-in/out that
 * the Identity screen can observe MUST go through `dispatchAction`, not the
 * legacy stub. The verified Rust contract (`identity_handler.rs`):
 *
 *  * `{"type":"ImportNsec","nsec":"nsec1…"}` — parse + persist + populate
 *    `active_account`.
 *  * `{"type":"Clear"}` — wipe the identity so `active_account` becomes null.
 *
 * Sign-out is `Clear`, NOT `ImportNsec` with an empty string — an empty nsec
 * hits `Keys::parse("")` → error → no-op (the identity would stick).
 */
object IdentityActions {
    const val NAMESPACE = "podcast.identity"

    private val json = Json

    /** Dispatch `ImportNsec` for [nsec]. Returns the kernel JSON envelope or null on FFI failure. */
    fun importNsec(bridge: KernelBridge, nsec: String): String? =
        bridge.dispatchAction(NAMESPACE, importNsecPayload(nsec))

    /** Dispatch `Generate` to create a fresh keypair. The kernel writes the new key
     *  to `identity.json` in the data dir — no Keystore entry needed (Keystore is
     *  only for imported nsec keys that the user may want to back up). */
    fun generate(bridge: KernelBridge): String? =
        bridge.dispatchAction(NAMESPACE, GENERATE_PAYLOAD)

    /** Dispatch `Clear` to sign out. Returns the kernel JSON envelope or null on FFI failure. */
    fun clear(bridge: KernelBridge): String? =
        bridge.dispatchAction(NAMESPACE, CLEAR_PAYLOAD)

    /** Build the `ImportNsec` payload with the nsec safely JSON-escaped. */
    fun importNsecPayload(nsec: String): String =
        json.encodeToString(
            JsonObject.serializer(),
            JsonObject(
                mapOf(
                    "type" to JsonPrimitive("ImportNsec"),
                    "nsec" to JsonPrimitive(nsec),
                ),
            ),
        )

    /**
     * Lightweight client-side format gate before we hand the key to the kernel.
     * The kernel's `Keys::parse` is the authoritative validator (and rejects on
     * the next snapshot via an unchanged `activeAccount`); this only catches the
     * obvious paste mistakes so the user gets immediate feedback.
     */
    fun isPlausibleNsec(input: String): Boolean {
        val trimmed = input.trim()
        return trimmed.startsWith("nsec1") && trimmed.length > 10
    }

    private const val CLEAR_PAYLOAD = "{\"type\":\"Clear\"}"
    private const val GENERATE_PAYLOAD = "{\"type\":\"Generate\"}"
}
