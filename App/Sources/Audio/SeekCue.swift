import AVFoundation
import Foundation
import os.log

// MARK: - SeekCue

/// Plays a short, soft tonal blip whenever the audio engine seeks — chapter
/// taps, scrubber commits, agent tool jumps, citation jumps, episode loads,
/// remote-control seeks, you name it. Audible cue that "something moved."
///
/// Around the blip, the cue ducks the main player's volume via the injected
/// `applyDuck` closure (sleep timer fades compose on top — see
/// `AudioEngine.applyEffectiveVolume`). The duck-play-restore choreography
/// runs on a single Task; back-to-back triggers cancel the in-flight task
/// and start fresh, so a fast double-seek doesn't fight itself.
///
/// The blip is synthesized at init time (a ~180 ms pitched tone with a
/// short attack, exponential decay, and a downward pitch glide) and written
/// to a WAV in the temp directory so `AVAudioPlayer` can load it. No
/// bundled asset, no Bundle.path resolution at runtime.
@MainActor
final class SeekCue {

    /// Apply a duck multiplier in [0, 1] to the main player's effective volume.
    /// `AudioEngine` wires this so the duck composes with `fadeBaseVolume`
    /// and the sleep-timer fade instead of fighting them.
    var applyDuck: (Float) -> Void = { _ in }

    // MARK: - Private

    private let logger = Logger.app("SeekCue")
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var lastFireTime: Date = .distantPast

    /// Coalesces tight bursts (e.g. `engine.load` immediately followed by
    /// `engine.seek(to: resumePosition)` in `PlaybackState.setEpisode`) into
    /// a single cue. Also dampens rapid chapter-next taps.
    private let minInterval: TimeInterval = 0.3

    /// Volume the main player dips to during the cue. 0.25 keeps speech
    /// audibly present but unmistakably ducked.
    private let duckLevel: Float = 0.25

    // MARK: - Init

    init() {
        prepare()
    }

    // MARK: - Public API

    /// Fire the cue. No-op when called within `minInterval` of the last fire.
    func trigger() {
        let now = Date()
        guard now.timeIntervalSince(lastFireTime) >= minInterval else { return }
        lastFireTime = now
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await self?.runDuckPlayRestore()
        }
    }

    // MARK: - Choreography

    private func runDuckPlayRestore() async {
        let duckSteps = 6
        let restoreSteps = 12
        let stepNanos: UInt64 = 18_000_000
        let holdNanos: UInt64 = 80_000_000

        // Kick the cue off immediately so its attack lines up with the start
        // of the duck — otherwise there's a beat of silence before the blip
        // while the main audio is still fading down.
        player?.currentTime = 0
        player?.play()

        for i in 1...duckSteps {
            if Task.isCancelled { return }
            let mult = 1.0 - (1.0 - duckLevel) * Float(i) / Float(duckSteps)
            applyDuck(mult)
            try? await Task.sleep(nanoseconds: stepNanos)
        }
        if Task.isCancelled { return }

        try? await Task.sleep(nanoseconds: holdNanos)
        if Task.isCancelled { applyDuck(1.0); return }

        for i in 1...restoreSteps {
            if Task.isCancelled { return }
            let mult = duckLevel + (1.0 - duckLevel) * Float(i) / Float(restoreSteps)
            applyDuck(mult)
            try? await Task.sleep(nanoseconds: stepNanos)
        }
        applyDuck(1.0)
    }

    // MARK: - Synthesis

    /// ~180 ms pitched tone, 1320 → 990 Hz downward glide, fundamental + a
    /// soft octave harmonic, linear attack + exponential decay envelope.
    /// Mono 16-bit PCM at 44.1 kHz — ~16 KB written to temp.
    private func prepare() {
        let sampleRate: Double = 44_100
        let duration: Double = 0.18
        let frameCount = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: frameCount)

        let attack: Double = 0.006
        let startFreq: Double = 1320
        let endFreq: Double = 990
        let peakAmplitude: Double = 0.32
        let twoPi = 2.0 * .pi

        var phase1: Double = 0
        var phase2: Double = 0
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let env: Double
            if t < attack {
                env = t / attack
            } else {
                let dt = (t - attack) / (duration - attack)
                env = exp(-dt * 5.0)
            }
            let freq = startFreq + (endFreq - startFreq) * progress
            phase1 += twoPi * freq / sampleRate
            phase2 += twoPi * freq * 2.0 / sampleRate
            let signal = sin(phase1) * 0.8 + sin(phase2) * 0.15
            let clipped = max(-1.0, min(1.0, signal * env * peakAmplitude))
            samples[i] = Int16(clipped * Double(Int16.max))
        }

        let wav = makeWav(samples: samples, sampleRate: Int(sampleRate))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seek-cue.wav")
        do {
            try wav.write(to: url, options: .atomic)
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 0.55
            p.prepareToPlay()
            player = p
        } catch {
            logger.error("Seek cue prepare failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wrap a 16-bit mono PCM sample array in a minimal RIFF/WAVE container.
    private func makeWav(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let dataBytes = samples.count * MemoryLayout<Int16>.size
        let chunkSize = 36 + dataBytes
        data.append(contentsOf: "RIFF".utf8)
        data.append(UInt32(chunkSize).leData)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(UInt32(16).leData)
        data.append(UInt16(1).leData)
        data.append(UInt16(1).leData)
        data.append(UInt32(sampleRate).leData)
        data.append(UInt32(sampleRate * 2).leData)
        data.append(UInt16(2).leData)
        data.append(UInt16(16).leData)
        data.append(contentsOf: "data".utf8)
        data.append(UInt32(dataBytes).leData)
        samples.withUnsafeBufferPointer { buf in
            data.append(Data(buffer: buf))
        }
        return data
    }
}

// MARK: - Little-endian byte helpers

private extension FixedWidthInteger {
    var leData: Data {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
