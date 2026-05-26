import AVFoundation
import Foundation

// Private implementation helpers for AgentTTSComposer.
// Split here to keep AgentTTSComposer.swift under the 500-line limit.

extension AgentTTSComposer {

    // MARK: - Track building

    /// Builds `BriefingTrack` values and returns the per-turn audio durations
    /// plus the surviving turns (turns whose audio loaded successfully).
    ///
    /// A turn is silently skipped — with an error log — when its audio asset
    /// fails to load or reports a zero duration. This prevents fictional
    /// durations from corrupting chapter start-time math. If every turn is
    /// skipped, throws `AgentTTSError.noPlayableContent`.
    func buildTracks(for turns: [TTSTurn]) async throws -> (
        tracks: [BriefingTrack],
        durations: [Double],
        survivingTurns: [TTSTurn]
    ) {
        var tracks: [BriefingTrack] = []
        var durations: [Double] = []
        var survivingTurns: [TTSTurn] = []
        let dummySegmentID = UUID()

        for (index, turn) in turns.enumerated() {
            switch turn.kind {
            case .speech(let text, let voiceIDOverride):
                let voice = voiceIDOverride ?? defaultVoiceID()
                let audioURL = try await synthesizeSpeech(text: text, voiceID: voice, index: index)
                let duration: TimeInterval
                do {
                    duration = try await audioDuration(of: audioURL)
                } catch {
                    Self.logger.error(
                        "AgentTTSComposer: skipping speech turn \(index, privacy: .public) — duration unavailable for \(audioURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    continue
                }
                tracks.append(BriefingTrack(
                    segmentID: dummySegmentID,
                    indexInSegment: index,
                    kind: .tts,
                    audioURL: audioURL,
                    startInTrackSeconds: 0,
                    endInTrackSeconds: duration,
                    transcriptText: text
                ))
                durations.append(duration)
                survivingTurns.append(turn)

            case .snippet(let episodeID, let start, let end, let label):
                let enclosureURL = try await resolveEpisodeAudio(episodeID: episodeID)
                let duration = end - start
                tracks.append(BriefingTrack(
                    segmentID: dummySegmentID,
                    indexInSegment: index,
                    kind: .quote,
                    audioURL: enclosureURL,
                    startInTrackSeconds: start,
                    endInTrackSeconds: end,
                    transcriptText: label ?? ""
                ))
                durations.append(duration)
                survivingTurns.append(turn)
            }
        }

        guard !tracks.isEmpty else {
            throw AgentTTSError.noPlayableContent
        }

        return (tracks, durations, survivingTurns)
    }

    // MARK: - Chapter + transcript building

    /// Converts the turn sequence into `Episode.Chapter` values and a
    /// `Transcript`. Consecutive speech turns collapse into a single chapter;
    /// each snippet turn gets its own chapter with the source episode's
    /// artwork URL and `sourceEpisodeID` set for the player chip.
    func buildChaptersAndTranscript(
        turns: [TTSTurn],
        trackDurations: [Double],
        episodeID: UUID
    ) async -> ([Episode.Chapter], Transcript) {
        var chapters: [Episode.Chapter] = []
        var transcriptSegments: [Segment] = []
        var cursor: TimeInterval = 0

        // Accumulator for consecutive speech turns.
        var speechStart: TimeInterval?
        var speechTexts: [String] = []

        func flushSpeechChapter() {
            guard !speechTexts.isEmpty, let start = speechStart else { return }
            let combinedText = speechTexts.joined(separator: " ")
            let preview = String(combinedText.prefix(60))
            let chapterTitle = combinedText.count <= 60 ? combinedText : preview + "…"
            chapters.append(Episode.Chapter(
                startTime: start,
                title: chapterTitle,
                isAIGenerated: true
            ))
            speechStart = nil
            speechTexts = []
        }

        // turns and trackDurations are guaranteed to be parallel and
        // contain only positive durations (buildTracks filters skipped tracks).
        for (index, turn) in turns.enumerated() {
            let duration = index < trackDurations.count ? trackDurations[index] : 0

            switch turn.kind {
            case .speech(let text, _):
                if speechStart == nil { speechStart = cursor }
                speechTexts.append(text)

                // Each speech turn is a transcript segment.
                transcriptSegments.append(Segment(
                    start: cursor,
                    end: cursor + duration,
                    text: text
                ))

            case .snippet(let sourceID, let snippetStart, _, let label):
                // Close any open speech chapter first.
                flushSpeechChapter()

                // Resolve the source episode's artwork for the mid-play swap.
                let artworkURL = await MainActor.run { [weak self] () -> URL? in
                    guard let self, let store = self.store else { return nil }
                    guard let uuid = UUID(uuidString: sourceID),
                          let ep = store.episode(id: uuid) else { return nil }
                    return ep.imageURL ?? store.podcast(id: ep.podcastID)?.imageURL
                }

                let chapterTitle: String
                if let nonEmpty = label, !nonEmpty.isEmpty {
                    chapterTitle = nonEmpty
                } else if let resolved = await resolveEpisodeTitle(episodeID: sourceID) {
                    chapterTitle = resolved
                } else {
                    // Episode not in store — use a time-anchored fallback so
                    // the chapter still has a meaningful label.
                    let minutes = Int(snippetStart) / 60
                    let seconds = Int(snippetStart) % 60
                    chapterTitle = String(format: "Quote at %d:%02d", minutes, seconds)
                }

                chapters.append(Episode.Chapter(
                    startTime: cursor,
                    title: chapterTitle,
                    imageURL: artworkURL,
                    isAIGenerated: true,
                    sourceEpisodeID: sourceID
                ))

                // Snippet text becomes a transcript segment too.
                if let labelText = label, !labelText.isEmpty {
                    transcriptSegments.append(Segment(
                        start: cursor,
                        end: cursor + duration,
                        text: labelText
                    ))
                }
            }

            cursor += duration
        }

        // Flush any trailing speech turns.
        flushSpeechChapter()

        let transcript = Transcript(
            episodeID: episodeID,
            language: "en",
            source: .onDevice,
            segments: transcriptSegments
        )

        return (chapters, transcript)
    }

    // MARK: - Speech synthesis → temp file

    func synthesizeSpeech(text: String, voiceID: String, index: Int) async throws -> URL {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-tts-\(index)-\(UUID().uuidString).mp3")

        var collectedData = Data()
        let stream = ttsClient.synthesizeStream(text: text, voiceID: voiceID)
        for try await chunk in stream {
            collectedData.append(chunk)
        }

        guard !collectedData.isEmpty else {
            throw AgentTTSError.emptyAudioData(index: index)
        }

        try collectedData.write(to: tmpURL, options: .atomic)
        Self.logger.debug("AgentTTSComposer: synthesised turn \(index, privacy: .public) → \(tmpURL.lastPathComponent, privacy: .public)")
        return tmpURL
    }

    // MARK: - Episode audio resolution

    /// Returns a local URL for the episode's audio, downloading it first if needed.
    /// Polls up to `timeout` seconds for the download to complete.
    func resolveEpisodeAudio(episodeID: EpisodeID, timeout: TimeInterval = 300) async throws -> URL {
        guard let uuid = UUID(uuidString: episodeID) else {
            throw AgentTTSError.snippetEpisodeNotFound(episodeID: episodeID)
        }

        // Check current state and trigger download if needed.
        let alreadyReady: URL? = await MainActor.run {
            guard let episode = store?.episode(id: uuid) else { return nil }
            if case .downloaded = episode.downloadState {
                let localURL = EpisodeDownloadStore.shared.localFileURL(for: episode)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    return localURL
                }
            }
            EpisodeDownloadService.shared.download(episodeID: uuid)
            return nil
        }
        if let url = alreadyReady { return url }

        // Episode not in store at all.
        let episodeExists = await MainActor.run { store?.episode(id: uuid) != nil }
        guard episodeExists else {
            throw AgentTTSError.snippetEpisodeNotFound(episodeID: episodeID)
        }

        Self.logger.info("AgentTTSComposer: waiting for download of snippet episode \(episodeID, privacy: .public)")

        // Poll until downloaded, failed, or timed out.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(1))

            let result: Result<URL, Error>? = await MainActor.run {
                guard let episode = store?.episode(id: uuid) else { return nil }
                switch episode.downloadState {
                case .downloaded:
                    let localURL = EpisodeDownloadStore.shared.localFileURL(for: episode)
                    return .success(localURL)
                case .failed(let message):
                    return .failure(AgentTTSError.snippetDownloadFailed(episodeID: episodeID, message: message))
                default:
                    return nil
                }
            }
            switch result {
            case .success(let url): return url
            case .failure(let error): throw error
            case nil: continue
            }
        }

        throw AgentTTSError.snippetDownloadTimeout(episodeID: episodeID)
    }

    /// Returns the episode title for the given ID, or `nil` when the episode
    /// cannot be found in the store.
    func resolveEpisodeTitle(episodeID: String) async -> String? {
        await MainActor.run {
            guard let uuid = UUID(uuidString: episodeID),
                  let episode = store?.episode(id: uuid) else {
                Self.logger.error(
                    "AgentTTSComposer: episode not found for chapter title lookup — episodeID=\(episodeID, privacy: .public)"
                )
                return nil
            }
            return episode.title
        }
    }

    // MARK: - Audio duration helper

    /// Loads the playback duration of an audio asset.
    ///
    /// Throws `AudioDurationError` on load failure or a zero/negative duration.
    /// Callers must skip the track rather than substituting a fictional length,
    /// which would corrupt chapter start-time math for all subsequent tracks.
    func audioDuration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds > 0 else {
                throw AudioDurationError.zeroDuration(url)
            }
            return seconds
        } catch let err as AudioDurationError {
            throw err
        } catch {
            throw AudioDurationError.assetLoadFailed(url, underlying: error)
        }
    }
}
