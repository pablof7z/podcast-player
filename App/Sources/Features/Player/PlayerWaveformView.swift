import SwiftUI

/// Fake waveform renderer using SwiftUI `Canvas`.
///
/// Draws (a) a synthesised amplitude curve and (b) per-line speaker-colored
/// stripes underneath the curve, communicating "the shape of the conversation"
/// per UX-01 §6.3. Lane 1 will replace the synthesised amplitudes with real
/// AVFoundation sample analysis — at that point this view's API stays stable;
/// only the `amplitudes(...)` source changes.
struct PlayerWaveformView: View {

    let duration: TimeInterval
    let currentTime: TimeInterval
    let transcript: [MockTranscriptLine]
    /// `true` while the user is actively dragging the scrubber — drives the
    /// 56pt → 220pt expansion described in the brief.
    let isScrubbing: Bool
    let copperAccent: Color

    /// Number of bars sampled across the full episode width. ~140 reads as
    /// "shape of the show" without becoming visual noise on phone screens.
    private let barCount: Int = 140

    var body: some View {
        Canvas { context, size in
            drawStripes(in: context, size: size)
            drawWaveform(in: context, size: size)
            drawPlayhead(in: context, size: size)
        }
        .accessibilityHidden(true) // semantics handled by the parent slider.
    }

    // MARK: - Drawing

    private func drawWaveform(in context: GraphicsContext, size: CGSize) {
        let waveformHeight = size.height * (isScrubbing ? 0.62 : 0.78)
        let baseline = size.height * 0.5
        let barWidth = size.width / CGFloat(barCount)
        let progressFraction = duration > 0 ? CGFloat(currentTime / duration) : 0

        for i in 0..<barCount {
            let normalized = CGFloat(i) / CGFloat(barCount - 1)
            let amplitude = synthAmplitude(at: normalized)
            let h = max(2, amplitude * waveformHeight)
            let x = CGFloat(i) * barWidth + barWidth * 0.15
            let rect = CGRect(
                x: x,
                y: baseline - h / 2,
                width: barWidth * 0.7,
                height: h
            )
            let played = normalized <= progressFraction
            let color = played ? copperAccent : copperAccent.opacity(0.28)
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth * 0.35),
                with: .color(color)
            )
        }
    }

    private func drawStripes(in context: GraphicsContext, size: CGSize) {
        guard isScrubbing, duration > 0 else { return }
        // Two stripes: top stripe = speaker A, bottom stripe = speaker B.
        // Lane 5 will produce a real diarization track; here we map by
        // alternating speakerID lanes.
        let stripeHeight: CGFloat = 6
        let topY = size.height * 0.86
        let bottomY = size.height * 0.94
        let firstSpeaker = transcript.first?.speakerID
        for line in transcript {
            let xStart = CGFloat(line.start / duration) * size.width
            let xEnd = CGFloat(line.end / duration) * size.width
            let y = line.speakerID == firstSpeaker ? topY : bottomY
            let rect = CGRect(
                x: xStart,
                y: y - stripeHeight / 2,
                width: max(2, xEnd - xStart),
                height: stripeHeight
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: stripeHeight / 2),
                with: .color(line.speakerColor.opacity(0.78))
            )
        }
    }

    private func drawPlayhead(in context: GraphicsContext, size: CGSize) {
        guard duration > 0 else { return }
        let x = CGFloat(currentTime / duration) * size.width
        let rect = CGRect(x: x - 1, y: size.height * 0.18, width: 2, height: size.height * 0.64)
        context.fill(Path(rect), with: .color(.white.opacity(0.9)))
        context.fill(
            Path(ellipseIn: CGRect(x: x - 5, y: size.height * 0.46, width: 10, height: 10)),
            with: .color(copperAccent)
        )
    }

    // MARK: - Amplitude synth

    /// Deterministic pseudo-amplitude in [0.18, 1.0]. Combines two sine waves
    /// + a slow envelope so the rendered shape reads as "speech-like" without
    /// real audio analysis.
    private func synthAmplitude(at normalized: CGFloat) -> CGFloat {
        let theta = normalized * .pi * 12
        let s1 = sin(theta) * 0.35
        let s2 = sin(theta * 2.7 + 1.3) * 0.25
        let envelope = 0.65 + 0.30 * sin(normalized * .pi)
        let raw = (s1 + s2) * envelope
        let absVal = abs(raw) + 0.18
        return min(max(absVal, 0.18), 1.0)
    }
}
