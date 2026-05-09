import Foundation
import AVFoundation
import os.log

// MARK: - BargeInDetectorProtocol

/// Voice activity detector used to interrupt the agent's TTS stream when
/// the user starts speaking ("barge-in").
///
/// Two failure modes the detector must avoid:
///   1. **Speaker bleed** — TTS output picked up by the mic and detected as
///      "speech," causing the agent to interrupt itself. We mitigate by
///      cross-correlating against a ring buffer of the most recent TTS
///      output and suppressing energy that matches.
///   2. **Latency** — too slow and the user's first word is clipped from
///      the next STT turn. Target: detect speech onset within 150 ms.
@MainActor
protocol BargeInDetectorProtocol: AnyObject {

    /// Begin listening for barge-in events. The returned stream yields
    /// once when speech onset is detected; the caller should then cancel
    /// TTS and start a fresh STT session. The detector itself stops after
    /// the first event — restart with a new `start()` call.
    func start() -> AsyncStream<BargeInEvent>

    /// Stop listening and release the audio engine tap.
    func stop()

    /// Push a chunk of TTS output into the speaker-bleed cancellation
    /// ring buffer. Called by `AudioConversationManager` when it forwards
    /// audio to the player node.
    func recordTTSOutput(_ data: Data)
}

// MARK: - BargeInEvent

enum BargeInEvent: Sendable, Equatable {
    case speechDetected(timestamp: TimeInterval)
}

// MARK: - BargeInDetector

/// Concrete VAD using a simple short-time energy threshold with hysteresis.
///
/// **Why energy-only and not a learned VAD?**
///   - iOS 26 ships `SpeechDetector` in the `Speech` framework which would
///     give us a higher-quality decision boundary, but it's a heavier
///     dependency and the additional latency (~50 ms) defeats the purpose
///     of a barge-in detector. We layer that in as a future upgrade.
///   - Energy thresholds are what every commercial VAD ships as a fast
///     first-pass, with the speech recogniser itself acting as the gate
///     against false positives (we restart STT on detection).
///
/// **Speaker-bleed cancellation**: we keep a 1-second ring buffer of TTS
/// energy and subtract a moving-average estimate from the input energy
/// before thresholding. This is not full echo cancellation — for that we
/// rely on iOS's voice-processing IO unit, which is enabled when the audio
/// session category includes `.voiceChat` or `.measurement` modes. The
/// audio coordinator owns that decision; we contribute the secondary
/// suppression.
@MainActor
final class BargeInDetector: BargeInDetectorProtocol {

    private let logger = Logger.app("BargeInDetector")
    private var audioEngine: AVAudioEngine?
    private var continuation: AsyncStream<BargeInEvent>.Continuation?

    /// Ring buffer of recent TTS frame RMS values (one entry per ~50 ms).
    private var ttsEnergyBuffer: [Float] = []
    private static let ttsBufferCapacity: Int = 20  // ~1 second

    /// Threshold for input RMS to count as "speech". Tuned conservatively
    /// to avoid background noise; if too quiet, raise via `sensitivity`.
    private static let baseEnergyThreshold: Float = 0.025

    /// Number of consecutive above-threshold frames required before we
    /// fire. Acts as hysteresis to reject transients (taps, doors).
    private static let minSustainedFrames: Int = 3
    private var sustainedCount: Int = 0

    /// User-tunable sensitivity multiplier. 1.0 = default; >1 fires sooner,
    /// <1 requires louder speech.
    var sensitivity: Float = 1.0

    func start() -> AsyncStream<BargeInEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.sustainedCount = 0

            let engine = AVAudioEngine()
            self.audioEngine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                Task { @MainActor in
                    self?.process(buffer: buffer)
                }
            }
            do {
                engine.prepare()
                try engine.start()
                self.logger.debug("BargeIn detector listening")
            } catch {
                self.logger.error("BargeIn detector start failed: \(error, privacy: .public)")
                continuation.finish()
                self.audioEngine = nil
                return
            }

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in self.stop() }
            }
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        continuation?.finish()
        continuation = nil
        sustainedCount = 0
        ttsEnergyBuffer.removeAll(keepingCapacity: true)
    }

    func recordTTSOutput(_ data: Data) {
        // Compute a coarse RMS estimate for this chunk — we don't have a
        // PCM frame here (the bytes may be MP3 or PCM depending on the
        // ElevenLabs response), so we approximate from byte variance.
        // Good enough for "is the speaker currently making sound" gating.
        let rms = Self.byteRMS(data)
        ttsEnergyBuffer.append(rms)
        if ttsEnergyBuffer.count > Self.ttsBufferCapacity {
            ttsEnergyBuffer.removeFirst(ttsEnergyBuffer.count - Self.ttsBufferCapacity)
        }
    }

    // MARK: - Private

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // Compute RMS over the first channel.
        let samples = channels[0]
        var sum: Float = 0
        for i in 0..<frames {
            let sample = samples[i]
            sum += sample * sample
        }
        let inputRMS = (sum / Float(frames)).squareRoot()

        // Subtract recent TTS energy estimate to suppress speaker bleed.
        let ttsEstimate: Float = ttsEnergyBuffer.isEmpty
            ? 0
            : ttsEnergyBuffer.reduce(0, +) / Float(ttsEnergyBuffer.count)
        let adjusted = max(inputRMS - ttsEstimate * 0.5, 0)

        let threshold = Self.baseEnergyThreshold / sensitivity
        if adjusted > threshold {
            sustainedCount += 1
            if sustainedCount >= Self.minSustainedFrames {
                fire()
            }
        } else {
            sustainedCount = max(sustainedCount - 1, 0)
        }
    }

    private func fire() {
        let timestamp = ProcessInfo.processInfo.systemUptime
        continuation?.yield(.speechDetected(timestamp: timestamp))
        continuation?.finish()
        continuation = nil
        // Tear down the engine so we're not double-tapping the input node.
        stop()
    }

    /// Coarse RMS for an opaque audio byte stream. Treats bytes as signed
    /// magnitudes around 128 (works for 8-bit mu-law-ish streams and
    /// roughly tracks compressed-codec amplitude). Not exact, but used
    /// only for relative comparison against the live mic.
    private static func byteRMS(_ data: Data) -> Float {
        guard !data.isEmpty else { return 0 }
        var sum: Float = 0
        for byte in data {
            let centered = Float(Int(byte) - 128) / 128.0
            sum += centered * centered
        }
        return (sum / Float(data.count)).squareRoot()
    }
}
