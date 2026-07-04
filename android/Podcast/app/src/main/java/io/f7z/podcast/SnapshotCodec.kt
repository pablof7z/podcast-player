package io.f7z.podcast

import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

// ── SnapshotCodec ─────────────────────────────────────────────────────────────

/**
 * Lazy JSON parser shared by the snapshot consumer.
 *
 * `decode` remains for the initial cold-start pull from `podcastSnapshot()`.
 * Steady-state `podcast.*` domain frames are decoded from typed projection
 * envelopes by [TypedProjectionDomainCodec], not by walking `v.projections`.
 */
object SnapshotCodec {
    val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    /**
     * Decode a bare projection payload — the shape `KernelBridge.podcastSnapshot()`
     * returns straight off the projection cache. Used for the initial cold-start paint.
     */
    fun decode(raw: String?): PodcastSnapshot? =
        raw?.let { runCatching { json.decodeFromString<PodcastSnapshot>(it) }.getOrNull() }

    /**
     * Decode generic NMP projection rows that still arrive through the JSON
     * bridge. `resolved_profiles` is not an app-owned `podcast.*` domain row,
     * so it remains outside [TypedProjectionDomainCodec].
     */
    fun decodeResolvedProfiles(raw: String?): Map<String, ResolvedProfile> {
        raw ?: return emptyMap()
        return runCatching {
            val outerObj = json.parseToJsonElement(raw) as? JsonObject ?: return@runCatching emptyMap()
            val v = outerObj["v"]?.jsonObject ?: return@runCatching emptyMap()
            val projections = v["projections"]?.jsonObject ?: return@runCatching emptyMap()
            val elem = projections["resolved_profiles"] ?: return@runCatching emptyMap()
            json.decodeFromJsonElement(
                MapSerializer(String.serializer(), ResolvedProfile.serializer()),
                elem,
            )
        }.getOrDefault(emptyMap())
    }

    /**
     * Merge present domain frames into a held [PodcastSnapshot] via copy().
     *
     * Per-domain drop-guard: if frame.rev <= tracker[domain], the frame is
     * stale and that domain slice is skipped (no clobber). The tracker is
     * updated in-place for each accepted domain.
     *
     * Tombstone handling: a domain's primary field arriving as null clears
     * that slice (e.g. identity.activeAccount = null → signed out).
     *
     * Returns the updated snapshot (may be the same instance if all domains
     * were stale), plus a flag indicating whether any domain was accepted.
     */
    fun mergeFrames(
        frames: PodcastDomainFrames,
        current: PodcastSnapshot,
        tracker: DomainRevTracker,
    ): Pair<PodcastSnapshot, Boolean> {
        var snap = current
        var anyAccepted = false

        // ── library ──────────────────────────────────────────────────────────
        frames.library?.let { lib ->
            if (lib.rev > tracker.library) {
                tracker.library = lib.rev
                anyAccepted = true
                snap = snap.copy(
                    // null = tombstone → clear to empty list
                    library  = lib.library ?: emptyList(),
                    podcasts = lib.library ?: emptyList(),
                    searchResults      = lib.searchResults ?: emptyList(),
                    inbox              = lib.inbox ?: emptyList(),
                    inboxTriageInProgress = lib.inboxTriageInProgress ?: false,
                    inboxLastTriagedAt = lib.inboxLastTriagedAt,
                )
            }
        }

        // ── playback ─────────────────────────────────────────────────────────
        frames.playback?.let { play ->
            if (play.rev > tracker.playback) {
                tracker.playback = play.rev
                anyAccepted = true
                snap = snap.copy(
                    nowPlaying = play.nowPlaying,
                    queue      = play.queue ?: emptyList(),
                )
            }
        }

        // ── downloads ────────────────────────────────────────────────────────
        frames.downloads?.let { dl ->
            if (dl.rev > tracker.downloads) {
                tracker.downloads = dl.rev
                anyAccepted = true
                // null = tombstone → no active downloads
                snap = snap.copy(downloads = dl.downloads)
            }
        }

        // ── settings ─────────────────────────────────────────────────────────
        frames.settings?.let { sett ->
            if (sett.rev > tracker.settings) {
                tracker.settings = sett.rev
                anyAccepted = true
                if (sett.settings != null) {
                    snap = snap.copy(settings = sett.settings)
                }
            }
        }

        // ── identity ─────────────────────────────────────────────────────────
        frames.identity?.let { ident ->
            if (ident.rev > tracker.identity) {
                tracker.identity = ident.rev
                anyAccepted = true
                // null = tombstone → signed out
                snap = snap.copy(activeAccount = ident.activeAccount)
            }
        }

        // ── widget ───────────────────────────────────────────────────────────
        frames.widget?.let { wid ->
            if (wid.rev > tracker.widget) {
                tracker.widget = wid.rev
                anyAccepted = true
                // null = tombstone → nothing to show
                snap = snap.copy(widget = wid.widget)
            }
        }

        // ── social ───────────────────────────────────────────────────────────
        // Kernel-authoritative: social moved out of podcast.misc.
        // nostrConversations + following are wired into PodcastSnapshot so the
        // conversations list, detail, and following screens can render directly.
        // Both fields are emitted atomically — a tombstone (social=null) clears
        // BOTH the follow list and the conversations list in one copy().
        // null = tombstone (account switch) → clear both to empty.
        frames.social?.let { soc ->
            if (soc.rev > tracker.social) {
                tracker.social = soc.rev
                anyAccepted = true
                snap = snap.copy(
                    nostrConversations = soc.nostrConversations ?: emptyList(),
                    following = soc.social?.following ?: emptyList(),
                    friends = soc.friends,
                )
            }
        }

        // ── voice ────────────────────────────────────────────────────────────
        // Voice state moved from podcast.misc to its own podcast.voice sidecar (PR #613).
        // null = tombstone (voice idle / conversation ended — clear prior state).
        frames.voice?.let { v ->
            if (v.rev > tracker.voice) {
                tracker.voice = v.rev
                anyAccepted = true
                snap = snap.copy(voice = v.voice)
            }
        }

        // ── misc ─────────────────────────────────────────────────────────────
        // NOTE: social moved to podcast.social (above).
        // NOTE: voice moved to podcast.voice (above).
        frames.misc?.let { m ->
            if (m.rev > tracker.misc) {
                tracker.misc = m.rev
                anyAccepted = true
                snap = snap.copy(
                    agentTasks      = m.agentTasks ?: snap.agentTasks,
                    feedbackEvents  = m.feedbackEvents ?: snap.feedbackEvents,
                    feedbackThreads = m.feedbackThreads ?: snap.feedbackThreads,
                    agent           = m.agent ?: snap.agent,
                    picks           = m.picks ?: snap.picks,
                    // clips: null = no change (retain prior); non-null = authoritative
                    // list from the kernel (may be empty if all clips deleted).
                    clips           = m.clips ?: snap.clips,
                )
            }
        }

        // ── resolved_profiles (additive, no rev gate) ─────────────────────────
        // The NMP kernel emits `projections["resolved_profiles"]` whenever a
        // claimed profile resolves (T114 reference-first profile resolution).
        // Unlike podcast domain sidecars, this map has no `rev` counter — it is
        // always an additive delta (entries only added, never removed mid-session).
        // Merging is a simple union: new entries from this frame win (the kernel
        // never downgrades a profile), existing entries without a new value are
        // retained from the composite. This mirrors iOS
        // `AppStateStore.mergeResolvedProfiles`.
        if (frames.resolvedProfiles.isNotEmpty()) {
            anyAccepted = true
            snap = snap.copy(
                resolvedProfiles = snap.resolvedProfiles + frames.resolvedProfiles,
            )
        }

        return Pair(snap, anyAccepted)
    }
}
