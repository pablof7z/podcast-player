import Foundation
import os

// MARK: - One-shot kernel knowledge re-backfill migration (Slice 4)
//
// Context: STT stores completed transcripts via `kernelTranscriptReport` →
// `set_transcript`, but `index_episode` was never dispatched. As a result
// the kernel KnowledgeStore is EMPTY even on a device with many transcribed
// episodes. This one-shot migration fires once after slice-4 ships and
// re-indexes every episode whose transcript is already in the kernel by
// dispatching `podcast.knowledge.index_episode` for each.
//
// Design constraints (memory: oneshot_migration_flag_after_work):
//   - Guard flag is set AFTER the dispatch loop, not before. A mid-loop
//     crash leaves no partial state — `index_episode` is idempotent
//     (deletes + re-upserts) — and the migration retries on next launch.
//   - Idempotent: safe to run multiple times; the kernel deduplicates.
//   - No data loss: vectors.sqlite is untouched. The Swift VectorIndex /
//     RAGService / agent adapter remain intact as dormant fallback (slice 5
//     territory).
//   - Reactive: waits for the first kernel snapshot via `awaitState` so we
//     don't race against a cold-start with no episodes yet.
//   - BM25 index populates synchronously on the kernel actor thread.
//     Semantic embeddings (embed transport) backfill off-actor automatically
//     on the next cold start via `spawn_backfill_embeddings`.

extension AppStateStore {

    /// UserDefaults key guarding the one-shot knowledge re-backfill.
    ///
    /// Versioned ("V1") so a future schema change can bump the suffix and
    /// force a re-index without needing to wipe the flag manually.
    private static let knowledgeBackfillFlagKey = "kernelKnowledgeBackfillV1"

    /// Wire point: call once from `attachKernel(_:)` after the kernel is
    /// attached and the data dir is bound. Fast-path no-op on every
    /// subsequent launch (UserDefaults guard).
    func backfillKernelKnowledge() {
        guard !UserDefaults.standard.bool(forKey: Self.knowledgeBackfillFlagKey) else { return }
        guard let kern = kernel else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            // Wait for the first kernel snapshot to populate `self.episodes`.
            // `awaitState` re-evaluates the closure on every observation tick
            // and returns the first non-nil value — no polling (project rule).
            //
            // The closure returns `nil` until the episode list is non-empty
            // (i.e. the first snapshot has landed); once populated it
            // immediately filters to the transcribed subset and returns it
            // (possibly an empty array on a device with no transcripts).
            let transcribedIDs: [UUID] = await awaitState(
                timeout: .seconds(60),
                body: { [weak self] () -> [UUID]? in
                    guard let self else { return nil }
                    // Keep waiting while the library hasn't arrived yet.
                    guard !self.episodes.isEmpty else { return nil }
                    return self.episodes.compactMap { episode -> UUID? in
                        guard case .ready = episode.transcriptState else { return nil }
                        return episode.id
                    }
                }
            ) ?? []

            // Even with zero transcribed episodes we mark done — the store
            // is indexed as-is and fresh transcripts arrive via the live
            // `index_episode` dispatch in the STT pipeline.
            guard !transcribedIDs.isEmpty else {
                UserDefaults.standard.set(true, forKey: Self.knowledgeBackfillFlagKey)
                os_log(.info,
                       log: OSLog(subsystem: "io.f7z.podcast", category: "KnowledgeBackfill"),
                       "Knowledge backfill: no transcribed episodes to index — done")
                return
            }

            os_log(.info,
                   log: OSLog(subsystem: "io.f7z.podcast", category: "KnowledgeBackfill"),
                   "Knowledge backfill: indexing %d transcribed episodes",
                   transcribedIDs.count)

            // Dispatch `index_episode` for every transcribed episode.
            // The kernel handler (`KnowledgeState::index_episode`) chunks the
            // stored transcript text synchronously on the actor thread and
            // stores NULL-embedding chunks; the embed transport fills them
            // off-actor, so BM25 search responds immediately and semantic
            // search degrades gracefully until the embedder catches up.
            for id in transcribedIDs {
                kern.dispatch(namespace: "podcast.knowledge",
                              body: ["op": "index_episode",
                                     "episode_id": id.uuidString])
            }

            // Flag set AFTER the dispatch loop (memory: oneshot_migration_flag_after_work).
            // Never set it before — a crash mid-loop leaves the migration
            // incomplete, but idempotency means the next launch fixes it.
            UserDefaults.standard.set(true, forKey: Self.knowledgeBackfillFlagKey)

            os_log(.info,
                   log: OSLog(subsystem: "io.f7z.podcast", category: "KnowledgeBackfill"),
                   "Knowledge backfill complete — %d episodes indexed into kernel KnowledgeStore",
                   transcribedIDs.count)
        }
    }
}
