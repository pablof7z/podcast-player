import Foundation

enum TypedProjectionGlue {
    static func library(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> LibraryDomainFrame? {
        decode(reader)
    }

    static func playback(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> PlaybackDomainFrame? {
        decode(reader)
    }

    static func downloads(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> DownloadsDomainFrame? {
        decode(reader)
    }

    static func settings(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> SettingsDomainFrame? {
        decode(reader)
    }

    static func identity(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> IdentityDomainFrame? {
        decode(reader)
    }

    static func widget(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> WidgetDomainFrame? {
        decode(reader)
    }

    static func social(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> SocialDomainFrame? {
        decode(reader)
    }

    static func voice(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> VoiceDomainFrame? {
        decode(reader)
    }

    static func misc(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> MiscDomainFrame? {
        decode(reader)
    }

    private static func decode<T: Decodable>(_ reader: podcastr_projection_PodcastProjectionJsonFrame) -> T? {
        guard reader.schemaVersion == 1, let json = reader.json else { return nil }
        return try? KernelDecoding.makeDecoder().decode(T.self, from: Data(json.utf8))
    }
}
