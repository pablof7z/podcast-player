import Foundation

/// Parses an OPML 2.0 subscription list into seeded `Podcast` records
/// ready for first refresh.
///
/// The OPML returned by Apple Podcasts, Pocket Casts, Overcast, Castro etc.
/// shares a common skeleton:
///
/// ```xml
/// <opml version="2.0">
///   <body>
///     <outline text="Podcasts">
///       <outline type="rss" text="Tim Ferriss"
///                xmlUrl="https://feeds.example/timferriss.rss"
///                htmlUrl="https://example/timferriss"
///                description="Author of …" />
///       …
///     </outline>
///   </body>
/// </opml>
/// ```
///
/// We seed preview `Podcast` rows from `xmlUrl` (the only required attribute)
/// plus whatever metadata is present. Episodes are *not* fetched here; confirmed
/// rows subscribe through the Rust kernel.
struct OPMLImport: Sendable {
    static let maxFileBytes = 5 * 1024 * 1024
    static let maxFeedCount = 5_000

    struct ParseIssue: Equatable, Sendable {
        var feedURLString: String?
        var title: String
        var message: String
    }

    struct ParseReport: Equatable, Sendable {
        var podcasts: [Podcast]
        var issues: [ParseIssue]
    }

    enum OPMLError: Error, LocalizedError, Sendable {
        case malformedXML(underlying: String)
        case fileTooLarge(limitBytes: Int)
        case tooManyFeeds(limit: Int)

        /// User-facing copy. `OPMLImportSheet` reads
        /// `error.localizedDescription` directly into the inline error
        /// label — without a `LocalizedError` conformance the user would
        /// see `malformedXML(underlying: "NSXMLParserErrorDomain error 5")`
        /// (Apple's `Error.localizedDescription` falls back to a raw
        /// `String(describing:)` for unconformed enums). Same trap that
        /// previously hit `RSSParser.ParseError`.
        var errorDescription: String? {
            switch self {
            case .malformedXML:
                return "This file isn't a valid OPML export. " +
                    "If you exported it from another podcast app, " +
                    "check that the export completed and try again."
            case .fileTooLarge(let limitBytes):
                let mb = max(1, limitBytes / 1_048_576)
                return "That OPML file is too large. Import files must be \(mb) MB or smaller."
            case .tooManyFeeds(let limit):
                return "That OPML file has more than \(limit) feeds. Split it into smaller imports and try again."
            }
        }
    }

    /// Parses raw OPML bytes. Outline nodes without an `xmlUrl` attribute are
    /// skipped (they are typically grouping folders). Order is preserved as
    /// emitted by the source app, so the Library import sheet can render the
    /// list as the user already knows it.
    func parseOPML(data: Data) throws -> [Podcast] {
        try parseOPMLReport(data: data).podcasts
    }

    /// Parses raw OPML bytes and returns both valid feeds and row-level issues
    /// for invalid entries. Bad feed URLs are partial failures, not whole-file
    /// failures, so a large OPML import can still bring over every valid feed.
    func parseOPMLReport(data: Data) throws -> ParseReport {
        guard data.count <= Self.maxFileBytes else {
            throw OPMLError.fileTooLarge(limitBytes: Self.maxFileBytes)
        }
        let delegate = OPMLImportDelegate(maxFeedCount: Self.maxFeedCount)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        guard parser.parse() else {
            if let failure = delegate.failure {
                throw failure
            }
            let underlying = parser.parserError?.localizedDescription ?? "unknown XMLParser error"
            throw OPMLError.malformedXML(underlying: underlying)
        }
        if let failure = delegate.failure {
            throw failure
        }
        return ParseReport(podcasts: delegate.podcasts, issues: delegate.issues)
    }
}

private final class OPMLImportDelegate: NSObject, XMLParserDelegate {
    var podcasts: [Podcast] = []
    var issues: [OPMLImport.ParseIssue] = []
    var failure: OPMLImport.OPMLError?

    private var seenFeedURLs: Set<URL> = []
    private let maxFeedCount: Int

    init(maxFeedCount: Int) {
        self.maxFeedCount = maxFeedCount
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline" else { return }
        // Per OPML 2.0 §6, podcast feeds carry `type="rss"` and `xmlUrl`; we
        // also accept `type="link"` plus `xmlUrl` (Castro emits this).
        guard let xmlUrlString = attributeDict["xmlUrl"],
              !xmlUrlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        let displayTitle = attributeDict["text"]?.nilIfBlank
            ?? attributeDict["title"]?.nilIfBlank
            ?? "Invalid feed URL"
        guard let feedURL = FeedURLNormalizer.normalizedFeedURL(from: xmlUrlString) else {
            issues.append(.init(
                feedURLString: xmlUrlString,
                title: displayTitle,
                message: "Only public http:// and https:// feed URLs can be imported."
            ))
            return
        }
        guard !seenFeedURLs.contains(feedURL) else { return }
        guard podcasts.count < maxFeedCount else {
            failure = .tooManyFeeds(limit: maxFeedCount)
            parser.abortParsing()
            return
        }
        seenFeedURLs.insert(feedURL)

        let title = attributeDict["text"]?.nilIfBlank
            ?? attributeDict["title"]?.nilIfBlank
            ?? feedURL.host
            ?? feedURL.absoluteString
        let description = attributeDict["description"] ?? ""
        let language = attributeDict["language"]

        let podcast = Podcast(
            feedURL: feedURL,
            title: title,
            description: description,
            language: language
        )
        podcasts.append(podcast)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
