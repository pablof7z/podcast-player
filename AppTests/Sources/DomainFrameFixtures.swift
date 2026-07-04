import FlatBuffers
import Foundation
@testable import Podcastr

enum DomainFrameFixtures {
    static func decode(from data: Data) -> PodcastDomainFrames? {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = raw["v"] as? [String: Any],
            let projections = value["projections"] as? [String: Any]
        else { return nil }

        let envelopes: [TypedProjectionEnvelope] = projections.compactMap { key, body in
            guard key.starts(with: "podcast.") else { return nil }
            guard JSONSerialization.isValidJSONObject(body),
                  let jsonData = try? JSONSerialization.data(withJSONObject: body),
                  let json = String(data: jsonData, encoding: .utf8)
            else { return nil }

            return TypedProjectionEnvelope(
                key: key,
                schemaId: key,
                schemaVersion: 1,
                fileIdentifier: "PJPR",
                payload: encodePjpr(json: json),
                projectionRev: projectionRev(body),
                state: .changed
            )
        }

        var frames = PodcastDomainFrames.decode(from: envelopes) ?? PodcastDomainFrames()
        frames.resolvedProfiles = PodcastDomainFrames.decodeResolvedProfiles(from: data)
        return frames.hasAnyDomain ? frames : nil
    }

    private static func encodePjpr(json: String) -> Data {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let root = podcastr_projection_PodcastProjectionJsonFrame
            .createPodcastProjectionJsonFrame(&fbb, schemaVersion: 1, jsonOffset: jsonOffset)
        podcastr_projection_PodcastProjectionJsonFrame.finish(&fbb, end: root)
        return Data(fbb.sizedByteArray)
    }

    private static func projectionRev(_ body: Any) -> UInt64 {
        guard let dict = body as? [String: Any] else { return 1 }
        if let rev = dict["rev"] as? UInt64 { return rev }
        if let rev = dict["rev"] as? Int { return UInt64(max(rev, 0)) }
        if let rev = dict["rev"] as? NSNumber { return rev.uint64Value }
        return 1
    }
}
