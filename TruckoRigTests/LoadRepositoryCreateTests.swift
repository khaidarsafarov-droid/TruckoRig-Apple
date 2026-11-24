import XCTest
@testable import TruckoRig

/// `LoadRepository.create` inserts a valid draft and refuses a second copy of the same trip.
@MainActor
final class LoadRepositoryCreateTests: XCTestCase {

    func testCreateInsertsAValidDraftAndReadsItBack() throws {
        let database = try AppDatabase.ephemeral()
        var saves = 0
        let repository = LoadRepository(database: database, onDidSave: { _ in saves += 1 })
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let created = try repository.create(
            LoadDraft(tripId: " new-9 ", date: when, totalRate: 1800, totalMiles: 420, rawMessage: "manual")
        )

        XCTAssertEqual(created.tripId, "NEW-9")
        XCTAssertEqual(saves, 1)
        let stored = try XCTUnwrap(database.load(tripId: "NEW-9"))
        XCTAssertEqual(stored.id, created.id)
        XCTAssertEqual(stored.totalRate, 1800, accuracy: 0.001)
        XCTAssertEqual(stored.totalMiles, 420, accuracy: 0.001)
        XCTAssertEqual(stored.rawMessage, "manual")
        XCTAssertEqual(stored.date.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCreateRejectsADuplicateTripId() throws {
        let database = try AppDatabase.ephemeral()
        let repository = LoadRepository(database: database)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try repository.create(LoadDraft(tripId: "dup-1", date: when, totalRate: 10, totalMiles: 1))

        XCTAssertThrowsError(
            try repository.create(LoadDraft(tripId: " DUP-1 ", date: when, totalRate: 12, totalMiles: 2))
        ) { error in
            XCTAssertEqual(error as? LoadRepositoryError, .duplicateTripId("DUP-1"))
        }
        XCTAssertEqual(try database.loads().count, 1)
        let stored = try XCTUnwrap(database.load(tripId: "DUP-1"))
        XCTAssertEqual(stored.totalRate, 10, accuracy: 0.001)
    }

    func testCreateRejectsAnInvalidDraft() throws {
        let database = try AppDatabase.ephemeral()
        let repository = LoadRepository(database: database)
        XCTAssertThrowsError(
            try repository.create(LoadDraft(tripId: "   ", totalRate: 0, totalMiles: -5))
        ) { error in
            guard case LoadRepositoryError.invalidDraft(let reasons) = error else {
                return XCTFail("expected an invalid draft, got \(error)")
            }
            XCTAssertFalse(reasons.isEmpty)
        }
        XCTAssertTrue(try database.loads().isEmpty)
    }
}
