import AVFoundation
import CoreMedia
import Foundation
import os.log
import Speech

// MARK: - AppleNativeSTTClient

/// Transcribes locally downloaded audio using iOS 26's `SpeechTranscriber` +
/// `SpeechAnalyzer` — fully on-device via Apple Silicon neural engine.
///
/// Why this exists over `SFSpeechRecognizer`:
///   • `SFSpeechRecognizer` has a ~1-minute practical limit on file-based requests;
///     podcast episodes are 30–120 min.
///   • The new `SpeechAnalyzer` API (iOS 26) handles long-form audio natively,
///     uses on-device models downloaded via `AssetInventory`, and is Swift-first
///     (`AsyncSequence`-based). No cloud round-trip, no API key required.
///
/// Constraint: requires a local `file://` URL. Episodes must be downloaded
/// before calling `transcribe`; the caller (`TranscriptIngestService`) is
/// responsible for surfacing a "download first" message when needed.
actor AppleNativeSTTClient {

    // MARK: Errors

    enum STTError: Error, LocalizedError, Sendable {
        case unavailable
        case requiresLocalFile
        case audioFileUnreadable(String)
        case modelUnavailableForLocale(String)
        case noResults

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "On-device speech recognition is not available on this device."
            case .requiresLocalFile:
                return "On-device transcription requires a downloaded episode. Download the episode first, then try again."
            case .audioFileUnreadable(let detail):
                return "Could not read the audio file: \(detail)"
            case .modelUnavailableForLocale(let locale):
                return "No on-device speech model is available for \(locale). The model may need to be downloaded — check Settings → General → Language & Region, or switch to ElevenLabs Scribe."
            case .noResults:
                return "Transcription produced no results. The audio may be too short or in an unsupported format."
            }
        }
    }

    private static let logger = Logger.app("AppleNativeSTTClient")

    // MARK: API

    /// Transcribes `audioFileURL` (must be a `file://` URL) and returns a
    /// `Transcript` using `TranscriptSource.onDevice`.
    ///
    /// Automatically downloads the on-device speech model for `languageHint`
    /// (defaults to `"en-US"`) if it is not already installed.
    func transcribe(
        audioFileURL: URL,
        episodeID: UUID,
        languageHint: String? = nil
    ) async throws -> Transcript {
        guard SpeechTranscriber.isAvailable else {
            throw STTError.unavailable
        }
        guard audioFileURL.isFileURL else {
            throw STTError.requiresLocalFile
        }

        let locale = resolveLocale(hint: languageHint)
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)

        try await ensureModelInstalled(for: transcriber, locale: locale)

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: audioFileURL)
        } catch {
            throw STTError.audioFileUnreadable(error.localizedDescription)
        }

        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )

        Self.logger.info(
            "on-device transcription starting — episode=\(episodeID, privacy: .public) locale=\(locale.identifier, privacy: .public)"
        )

        // Drive analysis and collect finalized segments concurrently.
        // `analyzeSequence` feeds audio through the pipeline; when it returns
        // the transcriber finalizes and its `results` sequence ends naturally.
        var rawResults: [SpeechTranscriber.Result] = []
        async let analysisTime: CMTime? = analyzer.analyzeSequence(from: audioFile)
        for try await result in transcriber.results where result.isFinal {
            rawResults.append(result)
        }
        _ = try await analysisTime

        Self.logger.info(
            "on-device transcription complete — episode=\(episodeID, privacy: .public) segments=\(rawResults.count, privacy: .public)"
        )

        guard !rawResults.isEmpty else {
            throw STTError.noResults
        }

        return Transcript.fromAppleResults(rawResults, episodeID: episodeID, locale: locale)
    }

    // MARK: Helpers

    private func resolveLocale(hint: String?) -> Locale {
        guard let hint, !hint.isEmpty else { return Locale(identifier: "en-US") }
        return Locale(identifier: hint)
    }

    private func ensureModelInstalled(
        for transcriber: SpeechTranscriber,
        locale: Locale
    ) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            throw STTError.modelUnavailableForLocale(locale.identifier)
        case .supported, .downloading:
            Self.logger.info("downloading on-device speech model for \(locale.identifier, privacy: .public)")
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw STTError.modelUnavailableForLocale(locale.identifier)
            }
            try await request.downloadAndInstall()
            Self.logger.info("on-device speech model installed for \(locale.identifier, privacy: .public)")
        }
    }
}
