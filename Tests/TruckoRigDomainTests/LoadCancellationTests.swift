import XCTest
@testable import TruckoRigDomain

/// Broker-cancelled loads (TONU): cancel, undo, the two-hour window, stats and backup keys.
final class LoadCancellationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func active(rate: Double = 1_850, miles: Double = 640, deadhead: Double = 42) -> LoadCancellationState {
        LoadCancellationState(totalRate: rate, totalMiles: miles, deadheadMiles: deadhead)
    }

    func testCancelSetsTonuZeroesLoadedMilesAndKeepsDeadhead() {
        let cancelled = LoadCancellation.cancel(active(), tonu: 175, now: now)

        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertEqual(cancelled.totalRate, 175)
        XCTAssertEqual(cancelled.totalMiles, 0)
        XCTAssertEqual(cancelled.deadheadMiles, 42)
        XCTAssertEqual(cancelled.drivenMiles, 42)
        XCTAssertEqual(cancelled.originalRate, 1_850)
        XCTAssertEqual(cancelled.originalMiles, 640)
        XCTAssertEqual(cancelled.cancelledAt, now)
        XCTAssertEqual(cancelled.tonuAmount, 175)
    }

    func testCancelWithoutPayIsAllowed() {
        let cancelled = LoadCancellation.cancel(active(), tonu: 0, now: now)

        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertEqual(cancelled.totalRate, 0)
        XCTAssertEqual(cancelled.tonuAmount, 0)
    }

    func testNegativeTonuIsClampedAndCentsAreRounded() {
        XCTAssertEqual(LoadCancellation.cancel(active(), tonu: -50, now: now).totalRate, 0)
        XCTAssertEqual(LoadCancellation.cancel(active(), tonu: 224.999, now: now).totalRate, 225)
    }

    func testCancellingAgainOnlyChangesTheTonuAndKeepsTheOriginals() {
        let first = LoadCancellation.cancel(active(), tonu: 175, now: now)
        let edited = LoadCancellation.cancel(first, tonu: 225, now: now.addingTimeInterval(600))

        XCTAssertEqual(edited.totalRate, 225)
        XCTAssertEqual(edited.originalRate, 1_850)
        XCTAssertEqual(edited.originalMiles, 640)
        XCTAssertEqual(edited.cancelledAt, now)
    }

    func testUndoRestoresRateAndMilesAndKeepsDeadhead() {
        let cancelled = LoadCancellation.cancel(active(), tonu: 225, now: now)
        let restored = LoadCancellation.undo(cancelled)

        XCTAssertEqual(restored, active())
        XCTAssertNil(restored.tonuAmount)
    }

    func testUndoOnAnActiveLoadChangesNothing() {
        XCTAssertEqual(LoadCancellation.undo(active()), active())
    }

    func testTonuWindowIsTwoHoursBeforePickupOrLater() {
        let pickup = now.addingTimeInterval(2 * 3_600)
        XCTAssertTrue(LoadCancellation.isWithinTonuWindow(pickup: pickup, now: now))
        XCTAssertTrue(LoadCancellation.isWithinTonuWindow(pickup: now.addingTimeInterval(-3_600), now: now))
        XCTAssertFalse(LoadCancellation.isWithinTonuWindow(pickup: pickup.addingTimeInterval(1), now: now))
        XCTAssertFalse(LoadCancellation.isWithinTonuWindow(pickup: nil, now: now))
    }

    func testSuggestedAmountPreselectsAmazonTonuOnlyInsideTheWindow() {
        let soon = now.addingTimeInterval(30 * 60)
        let later = now.addingTimeInterval(5 * 3_600)

        XCTAssertEqual(LoadCancellation.suggestedAmount(for: active(), pickup: soon, now: now), 175)
        XCTAssertNil(LoadCancellation.suggestedAmount(for: active(), pickup: later, now: now))
        let cancelled = LoadCancellation.cancel(active(), tonu: 300, now: now)
        XCTAssertEqual(LoadCancellation.suggestedAmount(for: cancelled, pickup: later, now: now), 300)
    }

    func testTonuValidation() {
        XCTAssertTrue(LoadCancellation.isValidTonu(0))
        XCTAssertTrue(LoadCancellation.isValidTonu(175))
        XCTAssertTrue(LoadCancellation.isValidTonu(LoadCancellation.maxTonu))
        XCTAssertFalse(LoadCancellation.isValidTonu(nil))
        XCTAssertFalse(LoadCancellation.isValidTonu(-1))
        XCTAssertFalse(LoadCancellation.isValidTonu(.nan))
        XCTAssertFalse(LoadCancellation.isValidTonu(LoadCancellation.maxTonu + 1))
    }

    func testCancelledLoadCountsTonuAsGrossForOneDay() {
        let pickup = makeDate(2026, 11, 16, 8)
        let cancelled = LoadSummary(
            totalRate: 175,
            totalMiles: 0,
            firstPickupAt: pickup,
            lastDeliveryAt: makeDate(2026, 11, 19, 8),
            isCancelled: true
        )
        let delivered = LoadSummary(
            totalRate: 2_000,
            totalMiles: 800,
            firstPickupAt: makeDate(2026, 11, 17, 8),
            lastDeliveryAt: makeDate(2026, 11, 18, 8)
        )

        XCTAssertEqual(LoadYieldCalculator.activeDurationDays(of: cancelled), 1)
        XCTAssertEqual(LoadYieldCalculator.resolvedDurationDays(of: cancelled), 1)
        XCTAssertEqual(LoadYieldCalculator.pace(of: cancelled), 175)
        XCTAssertEqual(LoadYieldCalculator.totalActiveDays([cancelled, delivered]), 2)
        XCTAssertEqual(LoadYieldCalculator.actualDailyYield([cancelled, delivered]), 1_087.5)
    }

    func testCancelledLoadWithoutMilesHasNoRateAndNoDivideByZero() {
        XCTAssertEqual(RPMCalculator.ratePerMile(rate: 175, miles: 0), 0)
        let record = LoadCSVRecord(
            tripId: "T-1",
            date: "2026-11-16",
            pointA: "",
            pointB: "",
            totalRate: 175,
            totalMiles: 42,
            isCancelled: true
        )
        XCTAssertEqual(record.ratePerMile, 0)
    }

    func testBackupRoundTripsCancellationWithAndroidKeys() throws {
        let load = BackupLoad(
            id: "77",
            tripId: "T-77",
            totalRateCents: 17_500,
            totalMiles: 0,
            deadheadMiles: 42,
            isCancelled: true,
            cancelledAt: 1_800_000_000_000,
            originalRateCents: 185_000,
            originalMiles: 640
        )
        let json = BackupDataCodec.encode(BackupData(schemaVersion: 2, version: 2, loads: [load]))

        XCTAssertTrue(json.contains(#""isCancelled":true"#))
        XCTAssertTrue(json.contains(#""cancelledAt":1800000000000"#))
        XCTAssertTrue(json.contains(#""originalRate":{"cents":185000}"#))
        XCTAssertTrue(json.contains(#""originalMiles":640"#))
        let decoded = try BackupDataCodec.decode(json)
        XCTAssertEqual(decoded.loads.first, load)
    }

    func testOlderBackupWithoutCancellationKeysReadsAsActive() throws {
        let json = #"{"schemaVersion":2,"loads":[{"id":"1","tripId":"T-1","totalRate":150000,"totalMiles":500}]}"#
        let load = try XCTUnwrap(BackupDataCodec.decode(json).loads.first)

        XCTAssertFalse(load.isCancelled)
        XCTAssertNil(load.cancelledAt)
        XCTAssertNil(load.originalRateCents)
        XCTAssertNil(load.originalMiles)
        XCTAssertFalse(BackupDataCodec.encode(BackupData(loads: [load])).contains("isCancelled"))
    }

    func testAndroidPlainNumberOriginalRateIsAccepted() throws {
        let row = #"{"id":"1","isCancelled":true,"totalRate":22500,"originalRate":99900,"originalMiles":12.5}"#
        let json = #"{"loads":["# + row + "]}"
        let load = try XCTUnwrap(BackupDataCodec.decode(json).loads.first)

        XCTAssertTrue(load.isCancelled)
        XCTAssertEqual(load.originalRateCents, 99_900)
        XCTAssertEqual(load.originalMiles, 12.5)
    }
}
