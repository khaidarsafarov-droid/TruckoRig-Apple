import XCTest
@testable import TruckoRigDomain

final class WeeklyGoalCalculatorTests: XCTestCase {

    private let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
    private lazy var calculator = WeeklyGoalCalculator(week: week, locale: Locale(identifier: "en_US"))
    /// Wednesday of the week Sun Aug 3 – Sat Aug 9, 2025.
    private let wednesday = makeDate(2025, 8, 6, 10, 0)

    private func currentWeekLoads(_ loads: [LoadSummary]) -> WeeklyGoalProgress {
        calculator.calculateCurrentWeek(target: 6000, loads: loads, now: wednesday)
    }

    func testEmptyWeekIsBehind() {
        let progress = currentWeekLoads([])

        XCTAssertEqual(progress.currentGross, 0, accuracy: 0.001)
        XCTAssertEqual(progress.remainingAmount, 6000, accuracy: 0.001)
        XCTAssertEqual(progress.paceStatus, .behind)
        XCTAssertEqual(progress.daysActiveCalendar, 4)
        XCTAssertEqual(progress.daysRemainingInWeek, 4)
        // Four calendar days into a seven-day week: an even pace would sit at 4/7 of the goal.
        XCTAssertEqual(progress.expectedGrossByNow, 3428.57, accuracy: 0.01)
    }

    func testGoalMetWinsOverPaceBands() {
        let load = LoadSummary.spanning(
            rate: 6200,
            from: makeDate(2025, 8, 4, 8, 0),
            to: makeDate(2025, 8, 6, 8, 0)
        )

        let progress = currentWeekLoads([load])

        XCTAssertEqual(progress.paceStatus, .goalMet)
        XCTAssertEqual(progress.progressPercent, 100, accuracy: 0.001)
        XCTAssertEqual(progress.remainingAmount, 0, accuracy: 0.001)
        XCTAssertEqual(progress.dailyTargetNeeded, 0, accuracy: 0.001)
    }

    func testAheadWhenDailyYieldBeatsTheRequiredPace() {
        // $3000 over two days is $1500/day; the remaining $3000 over four days needs $750/day.
        let load = LoadSummary.spanning(
            rate: 3000,
            from: makeDate(2025, 8, 4, 8, 0),
            to: makeDate(2025, 8, 6, 8, 0)
        )

        let progress = currentWeekLoads([load])

        XCTAssertEqual(progress.actualDailyYield, 1500, accuracy: 0.001)
        XCTAssertEqual(progress.dailyTargetNeeded, 750, accuracy: 0.001)
        XCTAssertEqual(progress.paceStatus, .ahead)
    }

    func testBehindWhenDailyYieldTrailsTheRequiredPace() {
        let load = LoadSummary.spanning(
            rate: 900,
            from: makeDate(2025, 8, 4, 8, 0),
            to: makeDate(2025, 8, 6, 8, 0)
        )

        let progress = currentWeekLoads([load])

        XCTAssertEqual(progress.actualDailyYield, 450, accuracy: 0.001)
        XCTAssertEqual(progress.dailyTargetNeeded, 1275, accuracy: 0.001)
        XCTAssertEqual(progress.paceStatus, .behind)
    }

    func testOnTrackTolerance() {
        // Two loads worth $2000 over two days: $1000/day against a $1000/day requirement.
        let loads = [
            LoadSummary.spanning(rate: 1000, from: makeDate(2025, 8, 3, 8, 0), to: makeDate(2025, 8, 4, 8, 0)),
            LoadSummary.spanning(rate: 1000, from: makeDate(2025, 8, 5, 8, 0), to: makeDate(2025, 8, 6, 8, 0)),
        ]

        let progress = currentWeekLoads(loads)

        XCTAssertEqual(progress.actualDailyYield, 1000, accuracy: 0.001)
        XCTAssertEqual(progress.dailyTargetNeeded, 1000, accuracy: 0.001)
        XCTAssertEqual(progress.paceStatus, .onTrack)
    }

    func testClosedWeekDoesNotTurnTheWholeGapIntoADailyTarget() {
        let lastWeek = week.shift(week.week(for: wednesday), by: -1)
        let load = LoadSummary.spanning(
            rate: 2000,
            from: makeDate(2025, 7, 28, 8, 0),
            to: makeDate(2025, 7, 29, 8, 0)
        )

        let progress = calculator.calculate(target: 6000, loads: [load], for: lastWeek, now: wednesday)

        XCTAssertEqual(progress.dailyTargetNeeded, 0, accuracy: 0.001)
        XCTAssertEqual(progress.daysRemainingInWeek, 1)
        XCTAssertEqual(progress.daysActiveCalendar, 7)
        XCTAssertEqual(progress.paceStatus, .behind)
    }

    func testClosedWeekThatHitTheGoalStillReportsGoalMet() {
        let lastWeek = week.shift(week.week(for: wednesday), by: -1)
        let load = LoadSummary.spanning(
            rate: 7000,
            from: makeDate(2025, 7, 28, 8, 0),
            to: makeDate(2025, 7, 31, 8, 0)
        )

        let progress = calculator.calculate(target: 6000, loads: [load], for: lastWeek, now: wednesday)

        XCTAssertEqual(progress.paceStatus, .goalMet)
    }

    func testZeroGoalNeverDividesByZero() {
        let progress = calculator.calculateCurrentWeek(target: 0, loads: [], now: wednesday)

        XCTAssertEqual(progress.progressPercent, 0, accuracy: 0.001)
        XCTAssertEqual(progress.dailyTargetNeeded, 0, accuracy: 0.001)
        XCTAssertEqual(progress.expectedGrossByNow, 0, accuracy: 0.001)
        XCTAssertEqual(progress.paceStatus, .behind)
    }

    func testWeekLabelAndTotalsAreReported() {
        let loads = [
            LoadSummary.spanning(rate: 1200, miles: 500, from: makeDate(2025, 8, 4, 8, 0), to: makeDate(2025, 8, 5, 8, 0)),
            LoadSummary.spanning(rate: 800, miles: 300, from: makeDate(2025, 8, 5, 8, 0), to: makeDate(2025, 8, 6, 8, 0)),
        ]

        let progress = currentWeekLoads(loads)

        XCTAssertEqual(progress.weekLabel, "Aug 3 – Aug 9, 2025")
        XCTAssertEqual(progress.loadsCount, 2)
        XCTAssertEqual(progress.totalMiles, 800, accuracy: 0.001)
        XCTAssertEqual(progress.totalActiveDays, 2, accuracy: 0.001)
    }
}
