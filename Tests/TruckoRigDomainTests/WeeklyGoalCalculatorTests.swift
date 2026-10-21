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

        // Pickup Tuesday through Wednesday is three calendar days, not the 48-hour duration.
        XCTAssertEqual(progress.actualDailyYield, 1000, accuracy: 0.001)
        XCTAssertEqual(progress.totalActiveDays, 3, accuracy: 0.001)
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

        XCTAssertEqual(progress.actualDailyYield, 300, accuracy: 0.001)
        XCTAssertEqual(progress.dailyTargetNeeded, 1275, accuracy: 0.001)
        XCTAssertEqual(progress.paceStatus, .behind)
    }

    func testOnTrackTolerance() {
        // $2000 across Tuesday and Wednesday is $1000/day, matching the $1000/day still required.
        let load = LoadSummary.spanning(
            rate: 2000,
            from: makeDate(2025, 8, 4, 8, 0),
            to: makeDate(2025, 8, 5, 8, 0)
        )

        let progress = currentWeekLoads([load])

        XCTAssertEqual(progress.actualDailyYield, 1000, accuracy: 0.001)
        XCTAssertEqual(progress.totalActiveDays, 2, accuracy: 0.001)
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
        // Aug 4–5 and Aug 5–6 share Wednesday, so the week has three on-road days.
        XCTAssertEqual(progress.totalActiveDays, 3, accuracy: 0.001)
    }

    func testGrossPrefersTheLargerOfSqlAndInMemoryLoads() {
        let day = makeDate(2026, 6, 10, 12, 0)
        let ref = week.week(for: day)
        let load = LoadSummary(totalRate: 2500, totalMiles: 800, filedOn: day, storedDurationDays: 1)

        let under = calculator.calculate(
            target: 5000,
            loads: [load],
            for: ref,
            sqlGross: 100,
            now: makeDate(2026, 10, 21, 12, 0)
        )

        XCTAssertEqual(under.currentGross, 2500, accuracy: 0.001)
        XCTAssertEqual(under.totalActiveDays, 1, accuracy: 0.001)
        XCTAssertEqual(under.actualDailyYield, 2500, accuracy: 0.001)

        let over = calculator.calculate(target: 5000, loads: [load], for: ref, sqlGross: 3000, now: makeDate(2026, 10, 21))
        XCTAssertEqual(over.currentGross, 3000, accuracy: 0.001)
        XCTAssertEqual(over.actualDailyYield, 3000, accuracy: 0.001)
    }

    func testOnRoadDaysStopAtTodayAndDoNotDoubleCountASharedDay() {
        let loads = [
            LoadSummary.spanning(rate: 1000, from: makeDate(2025, 8, 4, 8, 0), to: makeDate(2025, 8, 8, 18, 0)),
            LoadSummary.spanning(rate: 500, from: makeDate(2025, 8, 6, 9, 0), to: makeDate(2025, 8, 6, 20, 0)),
        ]
        let progress = currentWeekLoads(loads)
        // First load would run through Saturday, but today is Wednesday. The second load's
        // Wednesday is already covered.
        XCTAssertEqual(progress.totalActiveDays, 3, accuracy: 0.001)
    }

    func testSuggestedGoalsAndDayPlanFollowAndroid() {
        XCTAssertEqual(SuggestedWeeklyGoals.amounts(closedWeekGross: 0), [5000, 6000, 7000])
        XCTAssertEqual(SuggestedWeeklyGoals.amounts(closedWeekGross: 11_000), [10_000, 11_000, 11_500])
        XCTAssertEqual(SuggestedWeeklyGoals.chip(10_000), "10K")
        XCTAssertEqual(SuggestedWeeklyGoals.chip(11_500), "$11,500")
        XCTAssertEqual(WeeklyGoalInput.parseGoalAmount("2,500.50"), 2500.50)
        XCTAssertNil(WeeklyGoalInput.parseGoalAmount("abc"))

        let start = week.startDate(of: week.week(for: wednesday))!
        let rows = WeeklyDayPlan.rows(
            weekStart: start,
            today: wednesday,
            grossCentsBySqliteWeekday: [0: 0, 3: 250_000],
            dailyNeeded: MoneyCents.fromDollars(1_000),
            calendar: week.calendar
        )
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[0].status, .pastMissed)
        XCTAssertEqual(rows[3].status, .today)
        XCTAssertEqual(rows[3].gross.dollars, 2500, accuracy: 0.001)
        XCTAssertEqual(rows[3].planPercent, 250)
        XCTAssertEqual(rows[4].status, .future)
    }
}
