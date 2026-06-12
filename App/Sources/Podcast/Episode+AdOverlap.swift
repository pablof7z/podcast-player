import Foundation

// MARK: - Chapter overlap helper
//
// Relocated verbatim from the (now deleted) `AIChapterCompiler.swift` as part of
// the D0 consolidation that moved chapter + ad-span generation into the Rust
// kernel. `PlayerChaptersScrollView` uses it to flag ad-overlapping chapters
// with the amber stripe; `AdSegmentDetectorTests` exercises the same logic.

extension Episode.Chapter {
    /// `true` when this chapter's `[startTime, effectiveEnd)` window
    /// overlaps any of `adSegments`. `chapters` is the full list so the
    /// helper can resolve an implicit `endTime` from the next chapter's
    /// `startTime` when this chapter has no explicit `endTime`. For the last
    /// chapter we treat the end as `+∞` — any ad after `startTime` overlaps.
    func overlapsAd(
        in chapters: [Episode.Chapter],
        adSegments: [Episode.AdSegment]
    ) -> Bool {
        guard !adSegments.isEmpty else { return false }
        let effectiveEnd: TimeInterval
        if let end = endTime {
            effectiveEnd = end
        } else if let idx = chapters.firstIndex(where: { $0.id == id }),
                  chapters.index(after: idx) < chapters.endIndex {
            effectiveEnd = chapters[chapters.index(after: idx)].startTime
        } else {
            effectiveEnd = .greatestFiniteMagnitude
        }
        return adSegments.contains { ad in
            ad.start < effectiveEnd && ad.end > startTime
        }
    }
}
