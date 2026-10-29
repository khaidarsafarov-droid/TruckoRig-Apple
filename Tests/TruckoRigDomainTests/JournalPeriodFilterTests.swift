import XCTest
@testable import TruckoRigDomain

final class JournalPeriodFilterTests: XCTestCase {

    private let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
    private var now: Date { makeDate(2025, 8, 6, 12, 0) }

    func testYesterdayIsThePreviousCalendarDay() {
        XCTAssertTrue(includes(makeDate(2025, 8, 5), slice: .yesterday))
        XCTAssertFalse(includes(makeDate(2025, 8, 6), slice: .yesterday))
    }

    func testThisWeekUsesTheTruckingWeek() {
        XCTAssertTrue(includes(makeDate(2025, 8, 3), slice: .thisWeek))
        XCTAssertFalse(includes(makeDate(2025, 8, 2), slice: .thisWeek))
    }

    func testSelectedDateIsThatDayOnly() {
        XCTAssertTrue(includes(makeDate(2025, 8, 4), slice: .onDate, selected: makeDate(2025, 8, 4)))
        XCTAssertFalse(includes(makeDate(2025, 8, 5), slice: .onDate, selected: makeDate(2025, 8, 4)))
    }

    func testDateRangeIncludesBothEnds() {
        XCTAssertTrue(includes(makeDate(2025, 8, 4), slice: .dateRange, rangeStart: makeDate(2025, 8, 4), rangeEnd: makeDate(2025, 8, 6)))
        XCTAssertTrue(includes(makeDate(2025, 8, 6, 18, 0), slice: .dateRange, rangeStart: makeDate(2025, 8, 6), rangeEnd: makeDate(2025, 8, 4)))
        XCTAssertFalse(includes(makeDate(2025, 8, 7), slice: .dateRange, rangeStart: makeDate(2025, 8, 4), rangeEnd: makeDate(2025, 8, 6)))
    }

    func testSearchIgnoresALeadingHashAndMatchesTheISODate() {
        XCTAssertTrue(JournalSearch.matches(
            query: "#T-111",
            tripId: "T-111HLM7BD",
            places: ["Atlanta, GA", "CARLISLE, PA"],
            isoDates: ["2026-10-29", "2026-10-30"],
            displayDates: ["Thu, Oct 29"]
        ))
        XCTAssertTrue(JournalSearch.matches(
            query: "carlisle",
            tripId: "T-1",
            places: ["Atlanta, GA", "CARLISLE, PA"],
            isoDates: ["2026-10-29"],
            displayDates: []
        ))
        XCTAssertTrue(JournalSearch.matches(
            query: "2026-10-30",
            tripId: "T-1",
            places: [],
            isoDates: ["2026-10-29", "2026-10-30"],
            displayDates: []
        ))
        XCTAssertFalse(JournalSearch.matches(
            query: "Dallas",
            tripId: "T-1",
            places: ["Atlanta, GA"],
            isoDates: ["2026-10-29"],
            displayDates: ["Thu, Oct 29"]
        ))
    }

    func testADayInTransitMatchesTheChosenDay() {
        let pickup = makeDate(2025, 8, 4, 6, 30)
        let delivery = makeDate(2025, 8, 6, 18, 0)
        XCTAssertTrue(includes(pickup, slice: .onDate, selected: delivery, end: delivery))
        XCTAssertFalse(includes(pickup, slice: .onDate, selected: makeDate(2025, 8, 3), end: delivery))
        XCTAssertEqual(JournalPeriodFilter.activeDays(from: pickup, through: delivery, calendar: week.calendar).count, 3)
    }

    func testThisWeekFollowsTheReportingWeek() {
        let current = week.currentWeek(now: now)
        let previous = week.previousWeek(now: now)
        XCTAssertTrue(includes(makeDate(2025, 8, 2), slice: .thisWeek, reportingWeek: current))
        XCTAssertFalse(includes(makeDate(2025, 8, 6), slice: .thisWeek, reportingWeek: previous))
    }

    func testDisputesIgnoreTheDate() {
        XCTAssertTrue(includes(makeDate(2024, 1, 1), slice: .disputes, dispute: true))
        XCTAssertFalse(includes(now, slice: .disputes, dispute: false))
    }

    private func includes(
        _ date: Date,
        slice: JournalSlice,
        selected: Date? = nil,
        dispute: Bool = false,
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil,
        end: Date? = nil,
        reportingWeek: WeekRef? = nil
    ) -> Bool {
        JournalPeriodFilter.includes(
            date: date,
            activeDispute: dispute,
            unfinished: false,
            slice: slice,
            selectedDay: selected ?? now,
            week: week,
            rangeStart: rangeStart ?? now,
            rangeEnd: rangeEnd ?? now,
            now: now,
            end: end,
            reportingWeek: reportingWeek
        )
    }
}
