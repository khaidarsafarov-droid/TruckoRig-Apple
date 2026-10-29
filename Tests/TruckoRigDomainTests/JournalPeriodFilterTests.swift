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

    func testDisputesIgnoreTheDate() {
        XCTAssertTrue(includes(makeDate(2024, 1, 1), slice: .disputes, dispute: true))
        XCTAssertFalse(includes(now, slice: .disputes, dispute: false))
    }

    private func includes(
        _ date: Date,
        slice: JournalSlice,
        selected: Date? = nil,
        dispute: Bool = false
    ) -> Bool {
        JournalPeriodFilter.includes(
            date: date,
            activeDispute: dispute,
            unfinished: false,
            slice: slice,
            selectedDay: selected ?? now,
            week: week,
            now: now
        )
    }
}
