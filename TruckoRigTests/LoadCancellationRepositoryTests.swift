import XCTest
@testable import TruckoRig

/// "Load cancelled" (TONU) is written to the encrypted journal and "Restore load" undoes it.
@MainActor
final class LoadCancellationRepositoryTests: XCTestCase {

    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeLoad(_ repository: LoadRepository) throws -> Load {
        var draft = LoadDraft(tripId: "tonu-1", date: when, totalRate: 1_850, totalMiles: 640)
        draft.deadheadMiles = 42
        return try repository.create(draft)
    }

    func testCancelPersistsTonuZeroMilesAndKeepsDeadhead() throws {
        let database = try AppDatabase.ephemeral()
        let repository = LoadRepository(database: database)
        let load = try makeLoad(repository)

        try repository.cancel(load, tonu: 175, now: when)

        let stored = try XCTUnwrap(database.load(tripId: "TONU-1"))
        XCTAssertTrue(stored.isCancelled)
        XCTAssertEqual(stored.totalRate, 175, accuracy: 0.001)
        XCTAssertEqual(stored.totalMiles, 0, accuracy: 0.001)
        XCTAssertEqual(stored.deadheadMiles, 42, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stored.originalRate), 1_850, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stored.originalMiles), 640, accuracy: 0.001)
        XCTAssertEqual(stored.cancelledAt?.timeIntervalSince1970 ?? 0, when.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(stored.ratePerMile, 0)
        XCTAssertEqual(stored.durationDays, 1)
        XCTAssertEqual(try database.loads().count, 1)
    }

    func testRestoreBringsBackTheOriginalRateAndMiles() throws {
        let database = try AppDatabase.ephemeral()
        let repository = LoadRepository(database: database)
        let load = try makeLoad(repository)
        try repository.cancel(load, tonu: 0, now: when)

        try repository.restore(load)

        let stored = try XCTUnwrap(database.load(tripId: "TONU-1"))
        XCTAssertFalse(stored.isCancelled)
        XCTAssertEqual(stored.totalRate, 1_850, accuracy: 0.001)
        XCTAssertEqual(stored.totalMiles, 640, accuracy: 0.001)
        XCTAssertEqual(stored.deadheadMiles, 42, accuracy: 0.001)
        XCTAssertNil(stored.originalRate)
        XCTAssertNil(stored.originalMiles)
        XCTAssertNil(stored.cancelledAt)
    }

    func testLoadsSavedWithoutCancellationReadAsActive() throws {
        let database = try AppDatabase.ephemeral()
        let repository = LoadRepository(database: database)
        _ = try makeLoad(repository)

        let stored = try XCTUnwrap(database.load(tripId: "TONU-1"))
        XCTAssertFalse(stored.isCancelled)
        XCTAssertNil(stored.originalRate)
        XCTAssertGreaterThan(stored.ratePerMile, 0)
    }
}
