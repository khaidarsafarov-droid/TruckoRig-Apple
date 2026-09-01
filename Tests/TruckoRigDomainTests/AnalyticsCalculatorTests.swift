import XCTest
@testable import TruckoRigDomain

final class AnalyticsCalculatorTests: XCTestCase {

    private let calendar = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
    private let now = makeDate(2025, 8, 6, 10, 0)

    private func load(rate: Double, miles: Double, on date: Date, from: String = "NC", to: String = "OH") -> LoadSummary {
        LoadSummary(
            totalRate: rate,
            totalMiles: miles,
            firstPickupAt: date,
            lastDeliveryAt: date.addingTimeInterval(86_400),
            originState: from,
            destinationState: to
        )
    }

    func testWeeklySeriesKeepsEmptyWeeksAsGaps() {
        let loads = [
            load(rate: 2000, miles: 800, on: makeDate(2025, 8, 4)),
            load(rate: 1500, miles: 600, on: makeDate(2025, 7, 22)),
        ]

        let series = AnalyticsCalculator.weeklySeries(
            loads: loads,
            weeks: 4,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            now: now
        )

        XCTAssertEqual(series.count, 4)
        XCTAssertEqual(series.map(\.gross), [0, 1500, 0, 2000])
        XCTAssertEqual(series.last?.week, calendar.currentWeek(now: now))
    }

    func testWeeklySeriesReportsRatePerMile() {
        let series = AnalyticsCalculator.weeklySeries(
            loads: [load(rate: 2000, miles: 800, on: makeDate(2025, 8, 4))],
            weeks: 1,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(series.first?.ratePerMile ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(series.first?.loadCount, 1)
    }

    func testStateRevenueCreditsTheDeliveryState() {
        let loads = [
            load(rate: 2000, miles: 800, on: makeDate(2025, 8, 4), from: "NC", to: "OH"),
            load(rate: 1000, miles: 500, on: makeDate(2025, 8, 5), from: "OH", to: "TX"),
            load(rate: 1500, miles: 400, on: makeDate(2025, 8, 5), from: "TX", to: "OH"),
        ]

        let revenue = AnalyticsCalculator.stateRevenue(loads: loads)

        XCTAssertEqual(revenue.first?.state, "OH")
        XCTAssertEqual(revenue.first?.gross ?? 0, 3500, accuracy: 0.001)
        XCTAssertEqual(revenue.first?.loadCount, 2)
        XCTAssertEqual(revenue.last?.state, "TX")
    }

    func testStateRevenueFallsBackToOriginWhenDeliveryIsUnknown() {
        let revenue = AnalyticsCalculator.stateRevenue(
            loads: [load(rate: 900, miles: 300, on: makeDate(2025, 8, 4), from: "GA", to: "")]
        )

        XCTAssertEqual(revenue.map(\.state), ["GA"])
    }

    func testTopRoutesRankByGross() {
        let loads = [
            load(rate: 2000, miles: 800, on: makeDate(2025, 8, 4), from: "NC", to: "OH"),
            load(rate: 2200, miles: 900, on: makeDate(2025, 8, 5), from: "NC", to: "OH"),
            load(rate: 1000, miles: 400, on: makeDate(2025, 8, 5), from: "TX", to: "GA"),
        ]

        let routes = AnalyticsCalculator.topRoutes(loads: loads)

        XCTAssertEqual(routes.first?.id, "NC→OH")
        XCTAssertEqual(routes.first?.loadCount, 2)
        XCTAssertEqual(routes.first?.gross ?? 0, 4200, accuracy: 0.001)
        XCTAssertEqual(routes.first?.averageGross ?? 0, 2100, accuracy: 0.001)
        XCTAssertEqual(routes.count, 2)
    }

    func testMilesPerGallonUsesOdometerSpanAndLaterFills() {
        // 500 miles covered on the 80 gallons bought after the first reading.
        let mpg = AnalyticsCalculator.milesPerGallon(odometers: [
            (100_000, 70),
            (100_250, 40),
            (100_500, 40),
        ])

        XCTAssertEqual(mpg, 6.3, accuracy: 0.05)
    }

    func testMilesPerGallonNeedsTwoReadings() {
        XCTAssertEqual(AnalyticsCalculator.milesPerGallon(odometers: [(100_000, 70)]), 0, accuracy: 0.001)
        XCTAssertEqual(AnalyticsCalculator.milesPerGallon(odometers: []), 0, accuracy: 0.001)
    }
}
