import XCTest
@testable import TruckoRigDomain

/// The week total and the day plan have to count the same loads, including ones that have not
/// finished yet. Today in these cases is Wednesday, Oct 28, 2026.
final class WeekDayGrossTests: XCTestCase {

    private let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
    private let today = makeDate(2026, 10, 28, 11, 0)

    func testFuturePickupIsBookedOnItsDayAndStillInTheWeekTotal() {
        let ref = week.week(for: today)
        let loads = [
            AttributedLoad(pickup: makeDate(2026, 10, 26, 8, 0), finish: makeDate(2026, 10, 26, 20, 0), rate: 743),
            AttributedLoad(pickup: makeDate(2026, 10, 27, 8, 0), finish: makeDate(2026, 10, 27, 20, 0), rate: 1_359),
            AttributedLoad(pickup: makeDate(2026, 10, 29, 6, 30), finish: makeDate(2026, 10, 30, 10, 0), rate: 2_112),
        ]
        let buckets = WeekDayGross.centsBySqliteWeekday(loads: loads, week: week, ref: ref)
        let booked = WeekDayGross.bookedDollars(buckets)

        XCTAssertEqual(booked, 743 + 1_359 + 2_112, accuracy: 0.001)
        XCTAssertEqual(MoneyCents(cents: buckets[1] ?? 0).dollars, 743, accuracy: 0.001)
        XCTAssertEqual(MoneyCents(cents: buckets[2] ?? 0).dollars, 1_359, accuracy: 0.001)
        XCTAssertEqual(MoneyCents(cents: buckets[4] ?? 0).dollars, 2_112, accuracy: 0.001)

        let start = week.startDate(of: ref)!
        let needed = GoalMoneyMath.dailyTarget(goal: 7_000, totalGross: booked, daysRemaining: week.daysRemaining(in: ref, now: today))
        let rows = WeeklyDayPlan.rows(
            weekStart: start,
            today: today,
            grossCentsBySqliteWeekday: buckets,
            dailyNeeded: MoneyCents.fromDollars(needed),
            calendar: week.calendar
        )
        let thursday = rows[4]
        XCTAssertEqual(thursday.status, .future)
        XCTAssertEqual(thursday.gross.dollars, 2_112, accuracy: 0.001)
        XCTAssertEqual(rows[3].status, .today)
        XCTAssertEqual(rows[3].gross.dollars, 0, accuracy: 0.001)
        XCTAssertEqual(rows[5].status, .future)
        XCTAssertEqual(rows[5].gross.dollars, 0, accuracy: 0.001)
        // (7000 − 4214) / 4 remaining days, half-up to the cent.
        XCTAssertEqual(needed, 696.50, accuracy: 0.001)
    }

    func testPickupThatSlipsIntoThePreviousWeekLandsOnTheFinishDay() {
        let ref = week.week(for: today)
        let load = AttributedLoad(
            pickup: makeDate(2026, 10, 24, 18, 0),
            finish: makeDate(2026, 10, 25, 10, 0),
            rate: 900
        )
        let day = WeekDayGross.day(pickup: load.pickup, finish: load.finish, week: week, ref: ref)
        XCTAssertEqual(isoDay(day), "2026-10-25")
        let buckets = WeekDayGross.centsBySqliteWeekday(loads: [load], week: week, ref: ref)
        XCTAssertEqual(WeekDayGross.bookedDollars(buckets), 900, accuracy: 0.001)
        XCTAssertEqual(MoneyCents(cents: buckets[0] ?? 0).dollars, 900, accuracy: 0.001)
    }

    func testUnfinishedLoadWithNoDeliveryStillCountsOnThePickupDay() {
        let ref = week.week(for: today)
        let load = AttributedLoad(pickup: makeDate(2026, 10, 29, 6, 30), finish: nil, rate: 500)
        let buckets = WeekDayGross.centsBySqliteWeekday(loads: [load], week: week, ref: ref)
        XCTAssertEqual(MoneyCents(cents: buckets[4] ?? 0).dollars, 500, accuracy: 0.001)
        XCTAssertEqual(WeekDayGross.bookedDollars(buckets), 500, accuracy: 0.001)
    }
}
