import XCTest
@testable import TruckoRigDomain

final class LoadYieldCalculatorTests: XCTestCase {

    func testSameDayLoadCountsAsOneDay() {
        let load = LoadSummary.spanning(
            rate: 900,
            from: makeDate(2025, 8, 4, 6, 0),
            to: makeDate(2025, 8, 4, 18, 0)
        )

        XCTAssertEqual(LoadYieldCalculator.activeDurationDays(of: load), 1, accuracy: 0.001)
        XCTAssertEqual(LoadYieldCalculator.pace(of: load), 900, accuracy: 0.001)
    }

    func testPartialDaysRoundUp() {
        // 25 hours in transit is two days of the driver's week, not 1.04.
        let load = LoadSummary.spanning(
            rate: 1000,
            from: makeDate(2025, 8, 4, 6, 0),
            to: makeDate(2025, 8, 5, 7, 0)
        )

        XCTAssertEqual(LoadYieldCalculator.activeDurationDays(of: load), 2, accuracy: 0.001)
    }

    func testDriverFinishOverrideWinsOverLastDelivery() {
        let load = LoadSummary.spanning(
            rate: 1000,
            from: makeDate(2025, 8, 4, 6, 0),
            to: makeDate(2025, 8, 8, 6, 0),
            finish: makeDate(2025, 8, 5, 6, 0)
        )

        XCTAssertEqual(LoadYieldCalculator.activeDurationDays(of: load), 1, accuracy: 0.001)
        XCTAssertEqual(LoadYieldCalculator.pace(of: load), 1000, accuracy: 0.001)
    }

    func testDeliveryBeforePickupFallsBackToOneDay() {
        let load = LoadSummary.spanning(
            rate: 1000,
            from: makeDate(2025, 8, 6, 6, 0),
            to: makeDate(2025, 8, 4, 6, 0)
        )

        XCTAssertEqual(LoadYieldCalculator.activeDurationDays(of: load), 1, accuracy: 0.001)
    }

    func testStoredDurationIsUsedWhenScheduleIsMissing() {
        var load = LoadSummary(tripId: "T-1", totalRate: 1000)
        load.storedDurationDays = 3

        XCTAssertEqual(LoadYieldCalculator.resolvedDurationDays(of: load), 3, accuracy: 0.001)
    }

    func testScheduleWinsOverStoredDuration() {
        var load = LoadSummary.spanning(
            rate: 1000,
            from: makeDate(2025, 8, 4, 6, 0),
            to: makeDate(2025, 8, 5, 7, 0)
        )
        load.storedDurationDays = 9

        XCTAssertEqual(LoadYieldCalculator.resolvedDurationDays(of: load), 2, accuracy: 0.001)
    }

    func testWeekYieldDividesGrossByDaysInTransit() {
        let loads = [
            LoadSummary.spanning(rate: 1500, from: makeDate(2025, 8, 3, 6, 0), to: makeDate(2025, 8, 4, 6, 0)),
            LoadSummary.spanning(rate: 2500, from: makeDate(2025, 8, 5, 6, 0), to: makeDate(2025, 8, 7, 6, 0)),
        ]

        XCTAssertEqual(LoadYieldCalculator.totalActiveDays(loads), 3, accuracy: 0.001)
        XCTAssertEqual(LoadYieldCalculator.actualDailyYield(loads), 1333.33, accuracy: 0.01)
    }

    func testEmptyOrUnpaidWeekYieldsNothing() {
        XCTAssertEqual(LoadYieldCalculator.actualDailyYield([]), 0, accuracy: 0.001)
        let unpaid = LoadSummary.spanning(rate: 0, from: makeDate(2025, 8, 3), to: makeDate(2025, 8, 4))
        XCTAssertEqual(LoadYieldCalculator.actualDailyYield([unpaid]), 0, accuracy: 0.001)
    }

    func testRatePerMileBands() {
        XCTAssertEqual(RPMCalculator.ratePerMile(rate: 2500, miles: 850), 2.94, accuracy: 0.001)
        XCTAssertEqual(RPMCalculator.ratePerMile(rate: 2500, miles: 0), 0, accuracy: 0.001)
        XCTAssertEqual(RPMCalculator.band(for: 2.94), .good)
        XCTAssertEqual(RPMCalculator.band(for: 2.10), .acceptable)
        XCTAssertEqual(RPMCalculator.band(for: 1.40), .low)
        XCTAssertEqual(RPMCalculator.band(for: 0), .unknown)
    }

    func testTotalsRatePerMileUsesTotalsNotAnAverageOfRatios() {
        let totals = LoadTotals.of([
            LoadSummary(totalRate: 1000, totalMiles: 200),
            LoadSummary(totalRate: 1000, totalMiles: 800),
        ])

        XCTAssertEqual(totals.ratePerMile, 2.0, accuracy: 0.001)
    }

    func testThresholdValidation() {
        XCTAssertNil(RPMThresholds(minProfit: 2, targetProfit: 2.5).validationFailure)
        XCTAssertEqual(RPMThresholds(minProfit: 3, targetProfit: 2).validationFailure, .outOfOrder)
        XCTAssertEqual(RPMThresholds(minProfit: -1, targetProfit: 2).validationFailure, .negative)
    }
}
