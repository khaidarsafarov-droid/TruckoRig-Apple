import XCTest
@testable import TruckoRig

/// The app copies an inbox row into the journal and does not insert the same trip twice.
@MainActor
final class ShareImportProcessorTests: XCTestCase {

    private var roots: [URL] = []
    private var previousSeal: ((Data) throws -> Data)?
    private var previousOpen: ((Data) throws -> Data)?

    override func setUp() {
        super.setUp()
        previousSeal = ShareInboxCodec.seal
        previousOpen = ShareInboxCodec.open
        ShareInboxCodec.seal = nil
        ShareInboxCodec.open = nil
    }

    override func tearDown() {
        ShareInboxCodec.seal = previousSeal
        ShareInboxCodec.open = previousOpen
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
        super.tearDown()
    }

    func testImportWritesTheSharedLoadAndKeepsThePDF() throws {
        let harness = try makeHarness()
        let pdf = try Data(contentsOf: fixtureURL("text-layer.pdf"))
        _ = try harness.inbox.enqueue(record(id: UUID()), bytes: pdf)

        let outcome = ShareImportProcessor.importPending(
            loads: [],
            repository: harness.repository,
            media: harness.media,
            inboxRoot: harness.inbox.root
        )
        XCTAssertEqual(outcome.inserted.count, 1)
        XCTAssertEqual(outcome.duplicates, 0)
        let stored = try XCTUnwrap(harness.database.load(tripId: "SHARE-1"))
        XCTAssertEqual(stored.totalRate, 1500, accuracy: 0.001)
        XCTAssertEqual(stored.totalMiles, 500, accuracy: 0.001)
        XCTAssertEqual(stored.scans?.count ?? 0, 1)
        XCTAssertTrue(try harness.inbox.pending().isEmpty)
    }

    func testImportCountsADuplicateTripInsteadOfInsertingIt() throws {
        let harness = try makeHarness()
        _ = try harness.repository.create(
            LoadDraft(tripId: "SHARE-1", date: Date(), totalRate: 900, totalMiles: 100)
        )
        let pdf = try Data(contentsOf: fixtureURL("text-layer.pdf"))
        _ = try harness.inbox.enqueue(record(id: UUID()), bytes: pdf)
        let existing = try harness.database.loads()

        let outcome = ShareImportProcessor.importPending(
            loads: existing,
            repository: harness.repository,
            media: harness.media,
            inboxRoot: harness.inbox.root
        )
        XCTAssertTrue(outcome.inserted.isEmpty)
        XCTAssertEqual(outcome.duplicates, 1)
        XCTAssertEqual(try harness.database.loads().count, 1)
        let stored = try XCTUnwrap(harness.database.load(tripId: "SHARE-1"))
        XCTAssertEqual(stored.totalRate, 900, accuracy: 0.001)
    }

    private struct Harness {
        var database: AppDatabase
        var repository: LoadRepository
        var media: MediaRepository
        var inbox: ShareImportInbox
    }

    private func makeHarness() throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("truckorig-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let mediaRoot = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        let database = try AppDatabase.ephemeral()
        return Harness(
            database: database,
            repository: LoadRepository(database: database),
            media: MediaRepository(database: database, store: MediaStore(scope: .local, root: mediaRoot)),
            inbox: ShareImportInbox(root: root.appendingPathComponent("inbox", isDirectory: true))
        )
    }

    private func record(id: UUID) -> ShareImportRecord {
        ShareImportRecord(
            id: id,
            sourceText: "Trip SHARE-1 from Dallas to Atlanta",
            originalFileName: "text-layer.pdf",
            pageCount: 1,
            load: ShareLoadFields(
                tripId: "SHARE-1",
                broker: "Northwind",
                origin: "Dallas, TX",
                destination: "Atlanta, GA",
                pickupDate: nil,
                deliveryDate: nil,
                rate: 1500,
                miles: 500,
                missing: [],
                score: 80
            )
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle(for: SharePayloadReaderTests.self)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return try XCTUnwrap(bundle.url(forResource: base, withExtension: ext))
    }
}
