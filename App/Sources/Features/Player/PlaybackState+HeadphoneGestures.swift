import Foundation

// MARK: - Headphone gestures

extension PlaybackState {

    func performHeadphoneGesture(_ action: HeadphoneGestureAction) {
        switch action {
        case .skipForward:
            skipForward()
        case .skipBackward:
            skipBackward()
        case .nextChapter:
            let live = episode.flatMap { store?.episode(id: $0.id) } ?? episode
            let navigable = live?.chapters?.filter(\.includeInTableOfContents) ?? []
            if navigable.isEmpty { skipForward() } else { seekToNextChapter(in: navigable) }
        case .previousChapter:
            let live = episode.flatMap { store?.episode(id: $0.id) } ?? episode
            let navigable = live?.chapters?.filter(\.includeInTableOfContents) ?? []
            if navigable.isEmpty { skipBackward() } else { seekToPreviousChapter(in: navigable) }
        case .clipNow:
            AutoSnipController.shared.captureSnip(source: .headphone)
        case .none:
            break
        }
    }
}
