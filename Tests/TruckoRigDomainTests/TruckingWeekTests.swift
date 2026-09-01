import XCTest
@testable import TruckoRigDomain

final class TruckingWeekTests: XCTestCase {

    private let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)

    func testWeekStartsOnSunday() throws {
        // 2025-08-06 is a Wednesday; its week runs Sun Aug 3 – Sat Aug 9.
        let ref = week.week(for: makeDate(2025, 8, 6))
        let start = try XCTUnwrap(week.startDate(of: ref))
        let end = try XCTUnwrap(week.endDate(of: ref))

        XCTAssertEqual(isoDay(start), "2025-08-03")
        XCTAssertEqual(isoDay(end), "2025-08-09")
    }

    func testLateDecemberBelongsToNextWeekYear() {
        // Sunday 2025-12-28 opens week 1 of 2026 on a Sunday-start calendar.
        let ref = week.week(for: makeDate(2025, 12, 28))

        XCTAssertEqual(ref.weekNumber, 1)
        XCTAssertEqual(ref.year, 2026)
    }

    func testContainsCoversTheWholeWeek() {
        let ref = week.week(for: makeDate(2025, 8, 6))

        XCTAssertTrue(week.contains(makeDate(2025, 8, 3, 0, 1), in: ref))
        XCTAssertTrue(week.contains(makeDate(2025, 8, 9, 23, 59), in: ref))
        XCTAssertFalse(week.contains(makeDate(2025, 8, 10, 0, 1), in: ref))
    }

    func testShiftCrossesTheYearBoundary() {
        let firstWeekOf2026 = WeekRef(weekNumber: 1, year: 2026)
        let previous = week.shift(firstWeekOf2026, by: -1)

        XCTAssertEqual(previous.year, 2025)
        XCTAssertEqual(isoDay(week.startDate(of: previous)), "2025-12-21")
    }

    func testDaysElapsedAndRemaining() {
        let wednesday = makeDate(2025, 8, 6)

        XCTAssertEqual(week.daysElapsed(now: wednesday), 4)
        XCTAssertEqual(week.daysRemaining(now: wednesday), 4)
        XCTAssertEqual(week.daysElapsed(now: makeDate(2025, 8, 3)), 1)
        XCTAssertEqual(week.daysRemaining(now: makeDate(2025, 8, 9)), 1)
    }

    func testClosedWeeksReportFullActiveDaysAndOneRemaining() {
        let now = makeDate(2025, 8, 6)
        let lastWeek = week.shift(week.week(for: now), by: -1)

        XCTAssertEqual(week.daysActive(in: lastWeek, now: now), 7)
        XCTAssertEqual(week.daysRemaining(in: lastWeek, now: now), 1)
    }

    func testMondayStartShiftsBoundaries() throws {
        let mondayWeek = TruckingWeek(weekStart: .monday, timeZone: testTimeZone)
        let ref = mondayWeek.week(for: makeDate(2025, 8, 6))

        XCTAssertEqual(isoDay(mondayWeek.startDate(of: ref)), "2025-08-04")
        XCTAssertEqual(isoDay(mondayWeek.endDate(of: ref)), "2025-08-10")
        XCTAssertEqual(mondayWeek.daysElapsed(now: makeDate(2025, 8, 6)), 3)
    }

    func testWeekLabel() {
        let formatter = WeekLabelFormatter(week: week, locale: Locale(identifier: "en_US"))
        let ref = week.week(for: makeDate(2025, 8, 6))

        XCTAssertEqual(formatter.label(for: ref), "Aug 3 – Aug 9, 2025")
    }

    func testMonthLabelFollowsMidweekNotTheFirstDay() {
        let formatter = WeekLabelFormatter(week: week, locale: Locale(identifier: "en_US"))
        // Sun Aug 31 – Sat Sep 6, 2025: six of its seven days are September.
        let straddling = week.week(for: makeDate(2025, 9, 2))

        XCTAssertEqual(formatter.monthLabel(for: straddling), "September 2025")
        XCTAssertEqual(formatter.monthLabel(for: week.week(for: makeDate(2025, 8, 6))), "August 2025")
    }

    func testMonthMarkerOnlyAppearsOnTheFirstWeekOfAMonth() {
        let formatter = WeekLabelFormatter(week: week, locale: Locale(identifier: "en_US"))
        let first = week.week(for: makeDate(2025, 8, 6))
        let second = week.week(for: makeDate(2025, 8, 13))
        let nextMonth = week.week(for: makeDate(2025, 9, 10))

        XCTAssertEqual(formatter.monthMarker(for: first, after: nil), "August 2025")
        XCTAssertNil(formatter.monthMarker(for: second, after: first))
        XCTAssertEqual(formatter.monthMarker(for: nextMonth, after: second), "September 2025")
    }

    func testMonthMarkerCrossesTheYearBoundary() {
        let formatter = WeekLabelFormatter(week: week, locale: Locale(identifier: "en_US"))
        let december = week.week(for: makeDate(2025, 12, 17))
        let january = week.week(for: makeDate(2026, 1, 7))

        XCTAssertEqual(formatter.monthLabel(for: december), "December 2025")
        XCTAssertEqual(formatter.monthMarker(for: january, after: december), "January 2026")
    }
}
