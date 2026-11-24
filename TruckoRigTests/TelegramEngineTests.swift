import XCTest
@testable import TruckoRig

/// The long-poll engine with a scripted HTTP client: a failed poll, an offline catch-up, and a saved load.
@MainActor
final class TelegramEngineTests: XCTestCase {

    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    func testRunOnceRecordsAFailedGetUpdates() async throws {
        let transport = ScriptedTelegramTransport(
            getUpdates: .success(TelegramHTTPResponse(status: 500, body: "unavailable"))
        )
        let harness = try makeHarness(transport: transport)
        let outcome = await harness.engine.runOnce(token: token)
        XCTAssertTrue(outcome.failed)
        XCTAssertEqual(outcome.status, 500)
        XCTAssertEqual(outcome.processed, 0)
        XCTAssertTrue(try harness.database.loads().isEmpty)
        XCTAssertTrue(transport.urls.contains { $0.contains("/getUpdates") && $0.contains("timeout=25") })
    }

    func testCatchUpFailsOfflineWithoutWriting() async throws {
        let transport = ScriptedTelegramTransport(getUpdates: .failure(URLError(.notConnectedToInternet)))
        let harness = try makeHarness(transport: transport)
        let outcome = await harness.engine.catchUp(token: token)
        XCTAssertTrue(outcome.failed)
        XCTAssertEqual(outcome.processed, 0)
        XCTAssertTrue(try harness.database.loads().isEmpty)
        XCTAssertEqual(harness.prefs.offset, 0)
        XCTAssertTrue(transport.urls.contains { $0.contains("/getUpdates") && $0.contains("timeout=0") })
    }

    func testRunOnceWritesAParsedLoad() async throws {
        let text = """
        Trip ID: T-116KYL6KW
        Total Rate: 2500.00
        Total Loaded Miles: 850 mi
        Pu-address: SWF2, Garner, NC
        Del-address: TOL3, Perrysburg, OH
        """
        let body = try updatesJSON(chat: 7, text: text)
        let transport = ScriptedTelegramTransport(
            getUpdates: .success(TelegramHTTPResponse(status: 200, body: body))
        )
        let harness = try makeHarness(transport: transport)
        harness.prefs.chatId = 7
        let changes = JournalWrites()
        harness.engine.onJournalChanged = { _ in changes.value += 1 }

        let outcome = await harness.engine.runOnce(token: token)
        XCTAssertFalse(outcome.failed)
        XCTAssertEqual(outcome.processed, 1)
        XCTAssertEqual(harness.prefs.offset, 9)
        XCTAssertEqual(harness.prefs.lastLoadTrip, "T-116KYL6KW")
        XCTAssertGreaterThan(changes.value, 0)
        let stored = try XCTUnwrap(harness.database.load(tripId: "T-116KYL6KW"))
        XCTAssertEqual(stored.totalRate, 2500, accuracy: 0.001)
        XCTAssertEqual(stored.totalMiles, 850, accuracy: 0.001)
        XCTAssertEqual(stored.pointA ?? "", "Garner, NC")
        XCTAssertEqual(stored.pointB ?? "", "Perrysburg, OH")
    }

    private let token = "123456789:AAHabcdefghijklmnopqrstuvwxyz0123456789"

    private struct Harness {
        var database: AppDatabase
        var prefs: TelegramPrefs
        var engine: TelegramEngine
    }

    private func makeHarness(transport: ScriptedTelegramTransport) throws -> Harness {
        let name = "telegram-engine-\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let database = try AppDatabase.ephemeral()
        let settings = AppSettings(defaults: defaults, widgetDefaults: defaults)
        let prefs = TelegramPrefs(defaults: defaults)
        let engine = TelegramEngine(database: database, settings: settings, prefs: prefs, session: transport)
        return Harness(database: database, prefs: prefs, engine: engine)
    }

    private func updatesJSON(chat: Int, text: String) throws -> String {
        let payload: [String: Any] = [
            "ok": true,
            "result": [[
                "update_id": 8,
                "message": [
                    "message_id": 3,
                    "date": 1_700_000_000,
                    "text": text,
                    "chat": ["id": chat, "type": "private"],
                ],
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Counts journal writes from the engine callback without capturing a mutating local.
private final class JournalWrites: @unchecked Sendable {
    var value = 0
}

/// Records every URL and answers `getUpdates` from a script. Other methods succeed.
final class ScriptedTelegramTransport: TelegramTransport, @unchecked Sendable {
    var getUpdates: Result<TelegramHTTPResponse, Error>
    private(set) var urls: [String] = []

    init(getUpdates: Result<TelegramHTTPResponse, Error>) {
        self.getUpdates = getUpdates
    }

    func send(_ request: TelegramHTTPRequest) async throws -> TelegramHTTPResponse {
        urls.append(request.url)
        if request.url.contains("/getUpdates") {
            return try getUpdates.get()
        }
        return TelegramHTTPResponse(status: 200, body: #"{"ok":true,"result":true}"#)
    }

    func download(token: String, fileId: String) async throws -> Data {
        Data()
    }

    func setProfilePhoto(token: String, jpeg: Data) async -> Bool {
        true
    }
}
