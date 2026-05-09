import XCTest
@testable import AppTemplate

@MainActor
final class AppTests: XCTestCase {

    // MARK: - AppStateStore

    func testAddItem() throws {
        let store = AppStateStore()
        let initialCount = store.state.items.count

        store.addItem(title: "Test task")

        XCTAssertEqual(store.state.items.count, initialCount + 1)
        XCTAssertEqual(store.state.items.last?.title, "Test task")
        XCTAssertEqual(store.state.items.last?.status, .pending)
    }

    func testSetItemStatus() throws {
        let store = AppStateStore()
        let item = store.addItem(title: "Complete me")

        store.setItemStatus(item.id, status: .done)

        XCTAssertEqual(store.state.items.first { $0.id == item.id }?.status, .done)
    }

    func testDeleteItem() throws {
        let store = AppStateStore()
        let item = store.addItem(title: "Delete me")

        store.deleteItem(item.id)

        XCTAssertTrue(store.state.items.first { $0.id == item.id }?.deleted == true)
        XCTAssertFalse(store.activeItems.contains { $0.id == item.id })
    }

    func testAddFriend() throws {
        let store = AppStateStore()
        let friend = store.addFriend(displayName: "Alice", identifier: "alice@example.com")

        XCTAssertEqual(friend.displayName, "Alice")
        XCTAssertEqual(friend.identifier, "alice@example.com")
        XCTAssertTrue(store.state.friends.contains { $0.id == friend.id })
    }

    func testUpdateFriendDisplayName() throws {
        let store = AppStateStore()
        let friend = store.addFriend(displayName: "Bob", identifier: "bob_id")

        store.updateFriendDisplayName(friend.id, newName: "Robert")

        XCTAssertEqual(store.state.friends.first { $0.id == friend.id }?.displayName, "Robert")
    }

    func testRemoveFriend() throws {
        let store = AppStateStore()
        let friend = store.addFriend(displayName: "Charlie", identifier: "charlie_id")

        store.removeFriend(friend.id)

        XCTAssertFalse(store.state.friends.contains { $0.id == friend.id })
    }

    // MARK: - Models

    func testAnchorCodable() throws {
        let anchor = Anchor.item(id: UUID())
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(Anchor.self, from: data)
        XCTAssertEqual(anchor, decoded)
    }

    func testItemPeerAttribution() throws {
        let store = AppStateStore()
        let friend = store.addFriend(displayName: "Eve", identifier: "eve_id")

        let item = store.addItem(title: "Shared task", source: .agent, friendID: friend.id, friendName: friend.displayName)

        XCTAssertEqual(item.requestedByFriendID, friend.id)
        XCTAssertEqual(item.requestedByDisplayName, friend.displayName)
    }

    // MARK: - AgentPrompt

    func testAgentPromptIncludesFriends() {
        var state = AppState()
        state.friends.append(Friend(displayName: "Alice", identifier: "alice_id"))

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("Alice"))
    }

    func testAgentPromptIncludesMemories() {
        var state = AppState()
        state.agentMemories.append(AgentMemory(content: "User prefers mornings"))

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("User prefers mornings"))
    }

    func testSettingsDoesNotPersistLegacyOpenRouterAPIKey() throws {
        let json = """
        {
          "llmModel": "openai/gpt-4o-mini",
          "openRouterAPIKey": "sk-or-v1-secret",
          "agentMaxTurns": 12
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded.openRouterCredentialSource, .manual)
        XCTAssertEqual(decoded.legacyOpenRouterAPIKey, "sk-or-v1-secret")

        let encoded = try JSONEncoder().encode(decoded)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(encodedString.contains("sk-or-v1-secret"))
        XCTAssertFalse(encodedString.contains("openRouterAPIKey"))
    }

    func testSettingsPersistsBYOKMetadataOnly() throws {
        var settings = Settings()
        settings.markOpenRouterBYOK(keyID: "key_123", keyLabel: "Default")

        let encoded = try JSONEncoder().encode(settings)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""

        XCTAssertTrue(encodedString.contains("byok"))
        XCTAssertTrue(encodedString.contains("key_123"))
        XCTAssertTrue(encodedString.contains("Default"))
        XCTAssertFalse(encodedString.contains("api_key"))
    }

    // MARK: - DataExport

    func testDataExportRedactsLegacyOpenRouterKey() throws {
        var state = AppState()
        state.settings.legacyOpenRouterAPIKey = "sk-or-v1-leaked-secret"

        let payload = DataExport.makePayload(from: state)
        let data = try DataExport.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("sk-or-v1-leaked-secret"))
        XCTAssertNil(payload.state.settings.legacyOpenRouterAPIKey)
    }

    func testDataExportRoundTripsCoreRecords() throws {
        var state = AppState()
        state.items.append(Item(title: "Buy milk"))
        state.notes.append(Note(text: "Sample note"))
        state.friends.append(Friend(displayName: "Alice", identifier: "alice_id"))

        let data = try DataExport.encode(DataExport.makePayload(from: state))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DataExport.Payload.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, DataExport.currentSchemaVersion)
        XCTAssertEqual(decoded.state.items.first?.title, "Buy milk")
        XCTAssertEqual(decoded.state.notes.first?.text, "Sample note")
        XCTAssertEqual(decoded.state.friends.first?.displayName, "Alice")
    }

    func testDataExportStatsExcludeDeleted() {
        var state = AppState()
        let liveItem = Item(title: "Live")
        var ghost = Item(title: "Tombstone")
        ghost.deleted = true
        state.items = [liveItem, ghost]

        let liveNote = Note(text: "Live note")
        var deletedNote = Note(text: "Tombstone note")
        deletedNote.deleted = true
        state.notes = [liveNote, deletedNote]

        let stats = DataExport.stats(for: state)

        XCTAssertEqual(stats.items, 1)
        XCTAssertEqual(stats.notes, 1)
    }

    func testDataExportSuggestedFilenameShape() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        let date = f.date(from: "2026-05-05-1430")!

        let name = DataExport.suggestedFilename(at: date)
        XCTAssertEqual(name, "AppTemplate-Export-2026-05-05-1430.json")
    }

    func testDataExportWriteCreatesReadableFile() throws {
        var state = AppState()
        state.items.append(Item(title: "Persisted"))

        let url = try DataExport.writeExport(of: state)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DataExport.Payload.self, from: data)
        XCTAssertEqual(decoded.state.items.first?.title, "Persisted")
    }
}
