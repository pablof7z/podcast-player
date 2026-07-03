import Foundation

enum TypedProjectionState {
    case changed
    case cleared
}

struct TypedProjectionEnvelope {
    let key: String
    let schemaId: String
    let schemaVersion: UInt32
    let fileIdentifier: String
    let payload: Data
    let projectionRev: UInt64
    let state: TypedProjectionState
}

extension TypedProjectionEnvelope {
    init(_ envelope: PodcastTypedProjectionEnvelope) {
        self.key = envelope.key
        self.schemaId = envelope.schemaId
        self.schemaVersion = envelope.schemaVersion
        self.fileIdentifier = envelope.fileIdentifier
        self.payload = envelope.payload
        self.projectionRev = envelope.projectionRev
        switch envelope.state {
        case .changed:
            self.state = .changed
        case .cleared:
            self.state = .cleared
        }
    }
}
