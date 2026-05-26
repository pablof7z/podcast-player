import Foundation

/// A single episode belonging to a `PodcastSubscription`.
///
/// Field shape comes from the Lane 2 brief plus
/// `docs/spec/baseline-podcast-features.md` §1, §3 and the Podcasting 2.0
/// namespace mapping in `docs/spec/research/transcription-stack.md` §2.
///
/// `guid` is non-optional. RSS 2.0 specifies `<guid>` per item; when absent we
/// synthesize a stable string from the enclosure URL + pubDate (see
/// `RSSParser.synthesizedGUID(...)`). Lane 6 keys embedding rows off this
/// `guid`, so it must be deterministic across re-fetches.
struct Episode: Codable, Sendable, Identifiable, Hashable {
    /// Stable local identifier. Distinct from `guid`.
    var id: UUID
    /// Foreign key to the parent `Podcast.id`. Every episode has a real
    /// parent podcast — agent-added episodes without a known feed parent
    /// to `Podcast.unknownID`; TTS-generated episodes parent to the
    /// "Agent Generated" synthetic podcast row owned by
    /// `AgentGeneratedPodcastService`. There is no sentinel "no podcast"
    /// value.
    var podcastID: UUID
    /// Publisher's `<guid>` (or synthetic fallback). Used to dedupe across feed
    /// re-fetches and to key cross-system records (vector store, Spotlight).
    var guid: String

    var title: String
    /// Show notes / episode description (HTML or plain text).
    var description: String
    /// `<pubDate>` parsed via RFC 822 / RFC 1123.
    var pubDate: Date
    /// Episode duration in seconds. Comes from `<itunes:duration>`; format is
    /// either `H:MM:SS`, `MM:SS`, or raw seconds.
    var duration: TimeInterval?

    /// Direct media URL (`<enclosure url="…">`). Required for playback.
    var enclosureURL: URL
    /// Optional `<enclosure type="…">`, e.g. `audio/mpeg`.
    var enclosureMimeType: String?

    /// Per-episode artwork override (`<itunes:image>`). Falls back to the
    /// subscription's `imageURL` when nil.
    var imageURL: URL?

    // MARK: - Podcasting 2.0 enrichment

    /// Inline `<podcast:chapters>` content if the feed embedded chapters
    /// directly. Most feeds reference an external JSON instead via `chaptersURL`.
    var chapters: [Chapter]?
    /// `<podcast:person>` entries (host, guest, etc.) attached to the episode.
    var persons: [Person]?
    /// `<podcast:soundbite>` callouts: short hype clips authored by publisher.
    var soundBites: [SoundBite]?

    /// `<podcast:transcript url=…>` resolved URL when the publisher ships one.
    /// Lane 5 fetches and parses based on `publisherTranscriptType`.
    var publisherTranscriptURL: URL?
    /// Classified MIME type for `publisherTranscriptURL`. See `TranscriptKind`.
    var publisherTranscriptType: TranscriptKind?
    /// `<podcast:chapters url=… type=application/json+chapters>` JSON URL.
    var chaptersURL: URL?

    // MARK: - User-mutable playback state

    /// Last-known playback position in seconds. Persisted across launches.
    var playbackPosition: TimeInterval
    /// `true` once the user (or auto-played threshold) marked the episode done.
    var played: Bool
    /// User-flagged "starred" / favorite. Toggled from Library context menu.
    var isStarred: Bool
    /// Lifecycle of the local enclosure download.
    var downloadState: DownloadState
    /// Lifecycle of transcript ingestion.
    var transcriptState: TranscriptState
    /// Ad segments detected by `AIChapterCompiler` from the transcript. `nil`
    /// when detection hasn't been run yet (or the transcript wasn't ready);
    /// an empty array means detection ran and found no ads. Drives the
    /// auto-skip wiring in `PlaybackState` and the amber stripe on the
    /// chapter rail. Older saved state decodes via `decodeIfPresent` so the
    /// migration is silent.
    var adSegments: [AdSegment]?
    /// Non-nil for agent-generated episodes. Records where the generation was
    /// commissioned from so the player can surface a tappable source link.
    var generationSource: GenerationSource?

    /// Autonomous AI Inbox triage decision. `nil` until the triage pass has
    /// run for this episode. See `TriageDecision` for semantics. Drives both
    /// the Home Inbox surface (`.inbox`) and the silent-dismissal filtering
    /// for unplayed lists (`.archived`).
    var triageDecision: TriageDecision?

    /// One-line "because …" reason the agent surfaced this episode in the
    /// Inbox. Always populated when `triageDecision == .inbox`; `nil`
    /// otherwise (archived decisions are by design unreviewable per
    /// product brief, so no rationale is recorded for them).
    var triageRationale: String?

    /// `true` when the agent flagged this inbox pick as the hero card —
    /// the single episode the user should listen to first this pass.
    /// At most one episode per triage pass should carry this flag.
    var triageIsHero: Bool

    /// `true` once `EpisodeMetadataIndexer` has embedded the episode's
    /// title + description into the RAG index. Lets `search_episodes` /
    /// `find_similar_episodes` discover episodes that have no transcript.
    /// Flipped to `true` after a successful metadata upsert OR after a
    /// transcript ingestion lands real chunks for the episode (transcript
    /// chunks subsume the synthetic title/description match).
    var metadataIndexed: Bool

    init(
        id: UUID = UUID(),
        podcastID: UUID,
        guid: String,
        title: String,
        description: String = "",
        pubDate: Date,
        duration: TimeInterval? = nil,
        enclosureURL: URL,
        enclosureMimeType: String? = nil,
        imageURL: URL? = nil,
        chapters: [Chapter]? = nil,
        persons: [Person]? = nil,
        soundBites: [SoundBite]? = nil,
        publisherTranscriptURL: URL? = nil,
        publisherTranscriptType: TranscriptKind? = nil,
        chaptersURL: URL? = nil,
        playbackPosition: TimeInterval = 0,
        played: Bool = false,
        isStarred: Bool = false,
        downloadState: DownloadState = .notDownloaded,
        transcriptState: TranscriptState = .none,
        adSegments: [AdSegment]? = nil,
        generationSource: GenerationSource? = nil,
        triageDecision: TriageDecision? = nil,
        triageRationale: String? = nil,
        triageIsHero: Bool = false,
        metadataIndexed: Bool = false
    ) {
        self.id = id
        self.podcastID = podcastID
        self.guid = guid
        self.title = title
        self.description = description
        self.pubDate = pubDate
        self.duration = duration
        self.enclosureURL = enclosureURL
        self.enclosureMimeType = enclosureMimeType
        self.imageURL = imageURL
        self.chapters = chapters
        self.persons = persons
        self.soundBites = soundBites
        self.publisherTranscriptURL = publisherTranscriptURL
        self.publisherTranscriptType = publisherTranscriptType
        self.chaptersURL = chaptersURL
        self.playbackPosition = playbackPosition
        self.played = played
        self.isStarred = isStarred
        self.downloadState = downloadState
        self.transcriptState = transcriptState
        self.adSegments = adSegments
        self.generationSource = generationSource
        self.triageDecision = triageDecision
        self.triageRationale = triageRationale
        self.triageIsHero = triageIsHero
        self.metadataIndexed = metadataIndexed
    }

    // MARK: - Codable (forward-compat decoding)

    private enum CodingKeys: String, CodingKey {
        case id, podcastID, guid, title, description, pubDate, duration
        case enclosureURL, enclosureMimeType, imageURL
        case chapters, persons, soundBites
        case publisherTranscriptURL, publisherTranscriptType, chaptersURL
        case playbackPosition, played, isStarred, downloadState, transcriptState
        case adSegments, generationSource
        case triageDecision, triageRationale, triageIsHero
        case metadataIndexed
        // Legacy key from the pre-split shape. Decoded as a fallback when
        // `podcastID` is absent. Never written.
        case legacy_subscriptionID = "subscriptionID"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        if let pid = try c.decodeIfPresent(UUID.self, forKey: .podcastID) {
            podcastID = pid
        } else {
            // Pre-split persisted record: the FK was named `subscriptionID`.
            // Values remain valid because Podcast.id reuses the legacy UUID.
            podcastID = try c.decode(UUID.self, forKey: .legacy_subscriptionID)
        }
        guid = try c.decode(String.self, forKey: .guid)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        pubDate = try c.decodeIfPresent(Date.self, forKey: .pubDate) ?? Date(timeIntervalSince1970: 0)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        enclosureURL = try c.decode(URL.self, forKey: .enclosureURL)
        enclosureMimeType = try c.decodeIfPresent(String.self, forKey: .enclosureMimeType)
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        chapters = try c.decodeIfPresent([Chapter].self, forKey: .chapters)
        persons = try c.decodeIfPresent([Person].self, forKey: .persons)
        soundBites = try c.decodeIfPresent([SoundBite].self, forKey: .soundBites)
        publisherTranscriptURL = try c.decodeIfPresent(URL.self, forKey: .publisherTranscriptURL)
        publisherTranscriptType = try c.decodeIfPresent(TranscriptKind.self, forKey: .publisherTranscriptType)
        chaptersURL = try c.decodeIfPresent(URL.self, forKey: .chaptersURL)
        playbackPosition = try c.decodeIfPresent(TimeInterval.self, forKey: .playbackPosition) ?? 0
        played = try c.decodeIfPresent(Bool.self, forKey: .played) ?? false
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        downloadState = try c.decodeIfPresent(DownloadState.self, forKey: .downloadState) ?? .notDownloaded
        transcriptState = try c.decodeIfPresent(TranscriptState.self, forKey: .transcriptState) ?? .none
        adSegments = try c.decodeIfPresent([AdSegment].self, forKey: .adSegments)
        generationSource = try c.decodeIfPresent(GenerationSource.self, forKey: .generationSource)
        triageDecision = try c.decodeIfPresent(TriageDecision.self, forKey: .triageDecision)
        triageRationale = try c.decodeIfPresent(String.self, forKey: .triageRationale)
        triageIsHero = try c.decodeIfPresent(Bool.self, forKey: .triageIsHero) ?? false
        metadataIndexed = try c.decodeIfPresent(Bool.self, forKey: .metadataIndexed) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(podcastID, forKey: .podcastID)
        try c.encode(guid, forKey: .guid)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(pubDate, forKey: .pubDate)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encode(enclosureURL, forKey: .enclosureURL)
        try c.encodeIfPresent(enclosureMimeType, forKey: .enclosureMimeType)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
        try c.encodeIfPresent(chapters, forKey: .chapters)
        try c.encodeIfPresent(persons, forKey: .persons)
        try c.encodeIfPresent(soundBites, forKey: .soundBites)
        try c.encodeIfPresent(publisherTranscriptURL, forKey: .publisherTranscriptURL)
        try c.encodeIfPresent(publisherTranscriptType, forKey: .publisherTranscriptType)
        try c.encodeIfPresent(chaptersURL, forKey: .chaptersURL)
        try c.encode(playbackPosition, forKey: .playbackPosition)
        try c.encode(played, forKey: .played)
        try c.encode(isStarred, forKey: .isStarred)
        try c.encode(downloadState, forKey: .downloadState)
        try c.encode(transcriptState, forKey: .transcriptState)
        try c.encodeIfPresent(adSegments, forKey: .adSegments)
        try c.encodeIfPresent(generationSource, forKey: .generationSource)
        try c.encodeIfPresent(triageDecision, forKey: .triageDecision)
        try c.encodeIfPresent(triageRationale, forKey: .triageRationale)
        if triageIsHero { try c.encode(triageIsHero, forKey: .triageIsHero) }
        if metadataIndexed { try c.encode(metadataIndexed, forKey: .metadataIndexed) }
    }
}

