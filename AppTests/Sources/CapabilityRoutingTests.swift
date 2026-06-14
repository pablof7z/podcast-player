import Foundation
import XCTest
@testable import Podcastr

final class CapabilityRoutingTests: XCTestCase {
    func testSyncBridgeUsesInjectedHTTPExecutor() throws {
        let http = HttpCapability(timeout: 0.01)
        let bridge = SyncCapabilityBridge(http: http)

        XCTAssertTrue(http.isStarted)

        http.stop()
        let response = bridge.handle(
            requestJSON: makeCapabilityRequest(
                namespace: HttpCapability.namespace,
                payloadJSON: #"{"method":"GET","url":"https://example.com","headers":[]}"#))

        let envelope = try decodeEnvelope(response)
        let result = try decodeStatus(envelope.resultJSON)
        XCTAssertEqual(envelope.namespace, HttpCapability.namespace)
        XCTAssertEqual(result.status, "error")
        XCTAssertEqual(result.message, "capability-stopped")
    }

    @MainActor
    func testCapabilityHolderRoutesAsyncHTTPNamespace() throws {
        let http = HttpCapability(timeout: 0.01)
        http.start()
        let capabilities = PodcastCapabilities(http: http)

        let response = capabilities.handleJSON(
            makeCapabilityRequest(namespace: HttpCapability.asyncNamespace, payloadJSON: "{}"))

        let envelope = try decodeEnvelope(response)
        let result = try decodeStatus(envelope.resultJSON)
        XCTAssertEqual(envelope.namespace, HttpCapability.asyncNamespace)
        XCTAssertEqual(result.status, "accepted")
    }
}

private func makeCapabilityRequest(
    namespace: String,
    correlationID: String = "test-correlation",
    payloadJSON: String
) -> String {
    let object = [
        "namespace": namespace,
        "correlation_id": correlationID,
        "payload_json": payloadJSON,
    ]
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(data: data, encoding: .utf8)!
}

private func decodeEnvelope(_ json: String) throws -> TestCapabilityEnvelope {
    try JSONDecoder().decode(TestCapabilityEnvelope.self, from: Data(json.utf8))
}

private func decodeStatus(_ json: String) throws -> TestCapabilityStatus {
    try JSONDecoder().decode(TestCapabilityStatus.self, from: Data(json.utf8))
}

private struct TestCapabilityEnvelope: Decodable {
    let namespace: String
    let correlationID: String
    let resultJSON: String

    enum CodingKeys: String, CodingKey {
        case namespace
        case correlationID = "correlation_id"
        case resultJSON = "result_json"
    }
}

private struct TestCapabilityStatus: Decodable {
    let status: String
    let message: String?
}
