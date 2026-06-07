import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ElevenLabsVoiceBrowserViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
        case needsAPIKey
    }

    private(set) var phase: Phase = .idle
    private(set) var voices: [ElevenLabsVoice] = []
    private(set) var playingVoiceID: String?
    private(set) var loadingPreviewVoiceID: String?

    private let service = ElevenLabsVoicesService()
    private let player = PreviewPlayer()

    init() {
        Task { @MainActor [weak self] in
            let stream = NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime)
            for await _ in stream {
                guard let self else { return }
                self.handlePlaybackEnded()
            }
        }
    }

    func loadIfNeeded() async {
        guard voices.isEmpty, phase != .loading else { return }
        await reload()
    }

    func reload() async {
        phase = .loading
        do {
            let result = try await service.fetchVoices()
            voices = result
            phase = .loaded
        } catch ElevenLabsVoicesError.missingAPIKey {
            phase = .needsAPIKey
            voices = []
        } catch ElevenLabsVoicesError.unauthorized {
            phase = .needsAPIKey
            voices = []
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func togglePreview(for voice: ElevenLabsVoice) {
        if playingVoiceID == voice.voiceID {
            stopPreview()
            return
        }
        guard let url = voice.previewURL else { return }
        player.play(url: url)
        playingVoiceID = voice.voiceID
        loadingPreviewVoiceID = nil
        Haptics.light()
    }

    func stopPreview() {
        player.stop()
        playingVoiceID = nil
        loadingPreviewVoiceID = nil
    }

    private func handlePlaybackEnded() {
        playingVoiceID = nil
        loadingPreviewVoiceID = nil
    }

    // MARK: - PreviewPlayer

    private final class PreviewPlayer {
        private var player: AVPlayer?

        func play(url: URL) {
            player?.pause()
            configureElevenLabsAudioPlaybackSession()
            let item = AVPlayerItem(url: url)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.automaticallyWaitsToMinimizeStalling = false
            player = newPlayer
            newPlayer.play()
        }

        func stop() {
            player?.pause()
            player = nil
        }
    }
}
