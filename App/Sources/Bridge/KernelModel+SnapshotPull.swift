// KernelModel+SnapshotPull.swift
// Cold-start pull guard helper split out of KernelModel.swift to keep the
// race-prone comparison testable without exposing KernelModel's private state.

extension KernelModel {
    nonisolated static func shouldPullPodcastSnapshot(
        currentRev: UInt64,
        lastProcessedRev: UInt64,
        hasHydratedPodcastSnapshot: Bool
    ) -> Bool {
        if !hasHydratedPodcastSnapshot {
            return currentRev >= lastProcessedRev
        }
        return currentRev > lastProcessedRev
    }
}
