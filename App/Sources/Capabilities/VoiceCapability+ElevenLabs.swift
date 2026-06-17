import AVFoundation
import Foundation

// MARK: - ElevenLabs TTS playback sink
//
// When the user has selected an ElevenLabs voice, voice-mode `Speak`
// commands synthesize through the shared Rust transport
// (`ElevenLabsTTSBackendClient`, which owns provider URL/headers/body and
// returns decoded audio bytes) and play the result through an
// `AVAudioPlayer` here. Previously this executor logged the selection and
// fell back to `AVSpeechSynthesizer` because no playback sink existed — so
// a user who picked an ElevenLabs voice still heard the robotic on-device
// voice. This is that sink (docs/BACKLOG.md
// "voice-mode-elevenlabs-tts-playback-sink").
//
// Report mapping (mirrors the AVSpeech delegate):
//   • `.started`  — emitted once playback actually begins.
//   • `.finished` — emitted from the player completion callback.
//   • `.stopped`  — emitted by the `Stop` / barge-in canceller, not here
//                   (`AVAudioPlayer.stop()` does not call the delegate).
//
// On any failure (synthesis or playback construction) we fall back to
// `AVSpeechSynthesizer` so the turn is still spoken — matching the prior
// always-audible behaviour rather than dropping the utterance.
//
// File split out of `VoiceCapability.swift` to respect the 300-LOC soft
// limit (AGENTS.md).

extension VoiceCapability {
    /// Synthesize `text` via the shared Rust ElevenLabs transport and play
    /// the returned audio. Cancels any prior in-flight synth/playback so a
    /// new turn supersedes a stale one.
    func speakViaElevenLabs(text: String, voiceID: String, model: String, requestID: String) {
        cancelElevenLabsPlayback()

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelArg = trimmedModel.isEmpty ? nil : trimmedModel

        elevenLabsSynthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let audio = try await self.elevenLabsTTS.synthesize(
                    text: text,
                    voiceID: voiceID,
                    model: modelArg)
                // A `Stop` / barge-in that arrived while the round-trip was
                // in flight cancels this task — don't start stale audio.
                try Task.checkCancellation()
                self.elevenLabsSynthTask = nil
                self.playElevenLabsAudio(audio.data, fallbackText: text, requestID: requestID)
            } catch is CancellationError {
                // Superseded / stopped before playback — the canceller has
                // already reset state and emitted any report.
            } catch {
                self.elevenLabsSynthTask = nil
                self.logger.notice(
                    "ElevenLabs voice-mode TTS synthesis failed; falling back to AVSpeech: \(error.localizedDescription, privacy: .public)")
                self.speakViaAVSpeech(text: text, voiceID: nil, requestID: requestID)
            }
        }
    }

    /// Play synthesized audio bytes. Emits `.started` on success; on a
    /// playback-construction failure, falls back to AVSpeech.
    private func playElevenLabsAudio(_ data: Data, fallbackText: String, requestID: String) {
        do {
            configureElevenLabsAudioPlaybackSession()
            let player = try AVAudioPlayer(data: data, fileTypeHint: "mp3")
            let delegate = VoiceAudioPlayerDelegate { [weak self] in
                Task { @MainActor in self?.onElevenLabsPlaybackFinished(requestID: requestID) }
            }
            player.delegate = delegate
            player.prepareToPlay()
            elevenLabsPlayer = player
            elevenLabsPlayerDelegate = delegate
            guard player.play() else {
                throw ElevenLabsTTSBackendError.emptyAudio
            }
            activeSpeakRequestID = requestID
            emit(.started(requestID: requestID))
        } catch {
            logger.notice(
                "ElevenLabs voice-mode TTS playback failed; falling back to AVSpeech: \(error.localizedDescription, privacy: .public)")
            teardownElevenLabsPlayer()
            speakViaAVSpeech(text: fallbackText, voiceID: nil, requestID: requestID)
        }
    }

    /// Player completion callback — natural end of an ElevenLabs utterance.
    private func onElevenLabsPlaybackFinished(requestID: String) {
        // Ignore a stale callback from a player we already replaced.
        guard activeSpeakRequestID == requestID else { return }
        teardownElevenLabsPlayer()
        activeSpeakRequestID = nil
        emit(.finished(requestID: requestID))
    }

    /// Cancel any in-flight ElevenLabs synthesis and stop active playback.
    /// Does NOT emit a report — callers (`stopSpeaking`, barge-in) own the
    /// `.stopped` emission so it happens exactly once.
    func cancelElevenLabsPlayback() {
        elevenLabsSynthTask?.cancel()
        elevenLabsSynthTask = nil
        teardownElevenLabsPlayer()
    }

    /// Whether an ElevenLabs turn is currently synthesizing or playing.
    var isElevenLabsActive: Bool {
        elevenLabsSynthTask != nil || (elevenLabsPlayer?.isPlaying ?? false)
    }

    private func teardownElevenLabsPlayer() {
        elevenLabsPlayer?.stop()
        elevenLabsPlayer = nil
        elevenLabsPlayerDelegate = nil
    }
}

// MARK: - AVAudioPlayerDelegate forwarder
//
// Lets the `@MainActor` capability stay isolated while still hooking the
// completion callback off the audio player. Mirrors the pattern in
// `RationaleNarrator`.
final class VoiceAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish()
    }
}
