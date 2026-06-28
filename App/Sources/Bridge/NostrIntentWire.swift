import Foundation

// MARK: - NMP input-intent wire types

/// Registered NMP input scope id, serialized as `{"namespace":"...","name":"..."}`.
struct NostrIntentScope: Codable, Equatable {
    let namespace: String
    let name: String

    static let nostrRef = NostrIntentScope(namespace: "nostr", name: "ref")
    static let nip50Profiles = NostrIntentScope(namespace: "nip50", name: "profiles")
    static let nip50Notes = NostrIntentScope(namespace: "nip50", name: "notes")
}

enum NostrIntentTextTargets: Encodable, Equatable {
    case userPreferred

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .userPreferred:
            try container.encode("UserPreferred")
        }
    }
}

struct NostrIntentRequest: Encodable, Equatable {
    let input: String
    let scopes: [NostrIntentScope]
    let textTargets: NostrIntentTextTargets

    private enum CodingKeys: String, CodingKey {
        case input
        case scopes
        case textTargets = "text_targets"
    }

    func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct NostrIntentClassificationEnvelope: Decodable, Equatable {
    let ok: Bool
    let classification: NostrIntentClassification?
    let error: String?

    static func decode(json: String) -> NostrIntentClassificationEnvelope? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

enum NostrIntentClassification: Decodable, Equatable {
    case candidates([NostrIntentCandidate])
    case rejection(NostrIntentRejection)

    private enum CodingKeys: String, CodingKey {
        case Candidates
        case Rejection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let candidates = try container.decodeIfPresent(
            [NostrIntentCandidate].self,
            forKey: .Candidates
        ) {
            self = .candidates(candidates)
            return
        }
        if let rejection = try container.decodeIfPresent(
            NostrIntentRejection.self,
            forKey: .Rejection
        ) {
            self = .rejection(rejection)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unknown intent classification")
        )
    }
}

struct NostrIntentCandidate: Decodable, Equatable {
    let scope: NostrIntentScope?
    let target: NostrIntentTarget
}

enum NostrIntentDispatchOutcome: Equatable {
    case dispatched(NostrIntentTarget)
    case rejection(NostrIntentRejection)

    static func decode(json: String) -> NostrIntentDispatchOutcome? {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.ok else { return nil }
        if let candidate = envelope.dispatched {
            return .dispatched(candidate.target)
        }
        if let rejection = envelope.rejection {
            return .rejection(rejection)
        }
        return nil
    }

    private struct Envelope: Decodable {
        let ok: Bool
        let dispatched: NostrIntentCandidate?
        let rejection: NostrIntentRejection?
    }
}

enum NostrIntentTarget: Decodable, Equatable {
    case directRef(uri: String)
    case nip05(identifier: String)
    case relayURL(url: String)
    case textQuery
    case registered

    private enum CodingKeys: String, CodingKey {
        case DirectRef
        case Nip05
        case RelayUrl
        case TextQuery
        case Registered
    }

    private struct DirectRefBody: Decodable { let uri: String }
    private struct Nip05Body: Decodable { let identifier: String }
    private struct RelayURLBody: Decodable { let url: String }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let body = try container.decodeIfPresent(DirectRefBody.self, forKey: .DirectRef) {
            self = .directRef(uri: body.uri)
        } else if let body = try container.decodeIfPresent(Nip05Body.self, forKey: .Nip05) {
            self = .nip05(identifier: body.identifier)
        } else if let body = try container.decodeIfPresent(RelayURLBody.self, forKey: .RelayUrl) {
            self = .relayURL(url: body.url)
        } else if container.contains(.TextQuery) {
            self = .textQuery
        } else if container.contains(.Registered) {
            self = .registered
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "unknown intent target")
            )
        }
    }
}

enum NostrIntentRejection: Decodable, Equatable {
    case secretLike
    case unparseable
    case unregisteredScope
    case disallowedScope

    private enum ObjectKeys: String, CodingKey {
        case UnregisteredScope
        case DisallowedScope
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(String.self) {
            switch value {
            case "SecretLike":
                self = .secretLike
                return
            case "Unparseable":
                self = .unparseable
                return
            default:
                break
            }
        }
        let container = try decoder.container(keyedBy: ObjectKeys.self)
        if container.contains(.UnregisteredScope) {
            self = .unregisteredScope
        } else if container.contains(.DisallowedScope) {
            self = .disallowedScope
        } else {
            self = .unparseable
        }
    }
}

enum DecodedNostrRefTarget: Equatable {
    case profile(pubkey: String)
    case event(eventID: String)
    case address(pubkey: String)

    static func decode(json: String) -> DecodedNostrRefTarget? {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.ok else { return nil }
        switch envelope.target {
        case "profile":
            guard let pubkey = envelope.pubkey else { return nil }
            return .profile(pubkey: pubkey)
        case "event":
            guard let eventID = envelope.eventID else { return nil }
            return .event(eventID: eventID)
        case "address":
            guard let pubkey = envelope.pubkey else { return nil }
            return .address(pubkey: pubkey)
        default:
            return nil
        }
    }

    private struct Envelope: Decodable {
        let ok: Bool
        let target: String?
        let pubkey: String?
        let eventID: String?

        private enum CodingKeys: String, CodingKey {
            case ok
            case target
            case pubkey
            case eventID = "event_id"
        }
    }
}
