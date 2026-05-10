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
    /// Foreign key to the parent `PodcastSubscription.id`.
    var subscriptionID: UUID
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
    /// Lifecycle of the local enclosure download.
    var downloadState: DownloadState
    /// Lifecycle of transcript ingestion.
    var transcriptState: TranscriptState

    init(
        id: UUID = UUID(),
        subscriptionID: UUID,
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
        downloadState: DownloadState = .notDownloaded,
        transcriptState: TranscriptState = .none
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
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
        self.downloadState = downloadState
        self.transcriptState = transcriptState
    }

    // MARK: - Codable (forward-compat decoding)

    private enum CodingKeys: String, CodingKey {
        case id, subscriptionID, guid, title, description, pubDate, duration
        case enclosureURL, enclosureMimeType, imageURL
        case chapters, persons, soundBites
        case publisherTranscriptURL, publisherTranscriptType, chaptersURL
        case playbackPosition, played, downloadState, transcriptState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        subscriptionID = try c.decode(UUID.self, forKey: .subscriptionID)
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
        downloadState = try c.decodeIfPresent(DownloadState.self, forKey: .downloadState) ?? .notDownloaded
        transcriptState = try c.decodeIfPresent(TranscriptState.self, forKey: .transcriptState) ?? .none
    }
}

// MARK: - Podcasting 2.0 substructs

extension BidirectionalCollection where Element == Episode.Chapter {
    /// Returns the chapter that contains `playheadSeconds` — the last chapter
    /// whose `startTime <= playheadSeconds`. Falls back to the first chapter
    /// when the playhead sits before any chapter starts (typical at t=0
    /// before playback begins) so consumers always have an active indicator
    /// instead of a phantom none-selected state.
    func active(at playheadSeconds: TimeInterval) -> Episode.Chapter? {
        if let hit = self.last(where: { $0.startTime <= playheadSeconds }) {
            return hit
        }
        return self.first
    }
}

extension Episode {
    /// A chapter marker. Either inline (parsed from a `<podcast:chapter>`-like
    /// element) or hydrated later from `chaptersURL` JSON.
    struct Chapter: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        /// Start time in seconds from the beginning of the episode.
        var startTime: TimeInterval
        /// Optional end time. When `nil`, chapter ends at the next chapter or EOF.
        var endTime: TimeInterval?
        var title: String
        /// Optional `img` URL from Podcasting 2.0 chapters JSON.
        var imageURL: URL?
        /// Optional `url` reference (publisher show notes link).
        var linkURL: URL?
        /// `toc=false` chapters are non-navigable (e.g. ad markers).
        var includeInTableOfContents: Bool
        /// `true` when the chapter was synthesised by `AIChapterCompiler`
        /// from the transcript rather than parsed from a publisher source.
        /// Defaults to `false`; the player surfaces a subtle "AI" tag for true.
        var isAIGenerated: Bool

        init(
            id: UUID = UUID(),
            startTime: TimeInterval,
            endTime: TimeInterval? = nil,
            title: String,
            imageURL: URL? = nil,
            linkURL: URL? = nil,
            includeInTableOfContents: Bool = true,
            isAIGenerated: Bool = false
        ) {
            self.id = id
            self.startTime = startTime
            self.endTime = endTime
            self.title = title
            self.imageURL = imageURL
            self.linkURL = linkURL
            self.includeInTableOfContents = includeInTableOfContents
            self.isAIGenerated = isAIGenerated
        }

        private enum CodingKeys: String, CodingKey {
            case id, startTime, endTime, title, imageURL, linkURL
            case includeInTableOfContents, isAIGenerated
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            startTime = try c.decode(TimeInterval.self, forKey: .startTime)
            endTime = try c.decodeIfPresent(TimeInterval.self, forKey: .endTime)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
            linkURL = try c.decodeIfPresent(URL.self, forKey: .linkURL)
            includeInTableOfContents = try c.decodeIfPresent(Bool.self, forKey: .includeInTableOfContents) ?? true
            isAIGenerated = try c.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? false
        }
    }

    /// `<podcast:person>` — host / guest / cohost / etc.
    /// See podcasting2.org/docs/podcast-namespace/tags/person.
    struct Person: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        /// Display name (element text).
        var name: String
        /// `role` attribute: host, guest, cohost, …. Stored verbatim
        /// (case-insensitive); lower-cased for comparison.
        var role: String?
        /// `group` attribute (e.g. cast, writing). Optional.
        var group: String?
        /// `img` attribute — headshot URL.
        var imageURL: URL?
        /// `href` attribute — link to the person's homepage / social.
        var linkURL: URL?

        init(
            id: UUID = UUID(),
            name: String,
            role: String? = nil,
            group: String? = nil,
            imageURL: URL? = nil,
            linkURL: URL? = nil
        ) {
            self.id = id
            self.name = name
            self.role = role
            self.group = group
            self.imageURL = imageURL
            self.linkURL = linkURL
        }
    }

    /// `<podcast:soundbite>` — a short, publisher-curated highlight clip.
    struct SoundBite: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        /// `startTime` attribute, seconds.
        var startTime: TimeInterval
        /// `duration` attribute, seconds.
        var duration: TimeInterval
        /// Optional element text — a human-friendly title.
        var title: String?

        init(
            id: UUID = UUID(),
            startTime: TimeInterval,
            duration: TimeInterval,
            title: String? = nil
        ) {
            self.id = id
            self.startTime = startTime
            self.duration = duration
            self.title = title
        }
    }
}
