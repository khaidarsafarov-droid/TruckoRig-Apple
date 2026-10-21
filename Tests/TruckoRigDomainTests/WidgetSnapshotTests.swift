import XCTest
@testable import TruckoRigDomain

final class WidgetSnapshotTests: XCTestCase {

    private let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
    private let wednesday = makeDate(2025, 8, 6, 10, 0)

    func testSnapshotUsesGoalMathAndWeeklyRpm() {
        let calculator = WeeklyGoalCalculator(week: week, locale: Locale(identifier: "en_US"))
        let load = LoadSummary(
            totalRate: 11_606,
            totalMiles: 4_000,
            firstPickupAt: makeDate(2025, 8, 4, 8, 0),
            lastDeliveryAt: makeDate(2025, 8, 5, 8, 0)
        )
        let ref = week.currentWeek(now: wednesday)
        let progress = calculator.calculate(target: 13_000, loads: [load], for: ref, now: wednesday)
        let snapshot = WidgetSnapshotBuilder.make(
            progress: progress,
            weekStart: week.startDate(of: ref)!,
            weekEnd: week.endDate(of: ref)!,
            calendar: week.calendar,
            locale: Locale(identifier: "ru_RU"),
            now: wednesday
        )

        XCTAssertEqual(progress.remainingAmount, 1_394, accuracy: 0.001)
        XCTAssertEqual(progress.progressPercent, 11_606 / 13_000 * 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.gross, progress.currentGross, accuracy: 0.001)
        XCTAssertEqual(snapshot.remaining, progress.remainingAmount, accuracy: 0.001)
        XCTAssertEqual(snapshot.progressPercent, progress.progressPercent, accuracy: 0.001)
        XCTAssertEqual(snapshot.rpm, 11_606 / 4_000, accuracy: 0.001)
        XCTAssertEqual(snapshot.dailyTargetNeeded, progress.dailyTargetNeeded, accuracy: 0.001)
        XCTAssertFalse(snapshot.weekRange.isEmpty)
        XCTAssertTrue(snapshot.weekRange.contains("–"))
    }

    func testSplitWeekRangeSameMonthAndAcrossMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        let locale = Locale(identifier: "ru_RU")
        let same = SplitWeekRange.format(
            start: makeDate(2025, 10, 18),
            end: makeDate(2025, 10, 24),
            calendar: calendar,
            locale: locale
        )
        XCTAssertEqual(same, "18 – 24 \(monthName(makeDate(2025, 10, 24), calendar: calendar, locale: locale))")
        XCTAssertFalse(same.contains("."))

        let crossing = SplitWeekRange.format(
            start: makeDate(2025, 12, 28),
            end: makeDate(2026, 1, 3),
            calendar: calendar,
            locale: locale
        )
        XCTAssertTrue(crossing.hasPrefix("28 "))
        XCTAssertTrue(crossing.contains(" – 3 "))

        let home = SplitWeekRange.homeCaption(
            start: makeDate(2025, 10, 18),
            end: makeDate(2025, 10, 24),
            calendar: calendar,
            locale: locale
        )
        XCTAssertTrue(home.contains("18"))
        XCTAssertTrue(home.contains("24"))
        XCTAssertTrue(home.contains("–"))
    }

    func testRingPercentDropsNoiseAndKeepsARealTenth() {
        XCTAssertEqual(USMoneyFormat.ringPercent(89), "89%")
        XCTAssertEqual(USMoneyFormat.ringPercent(89.02), "89%")
        XCTAssertEqual(USMoneyFormat.ringPercent(89.28), "89.3%")
        XCTAssertEqual(USMoneyFormat.currency(11_606), "$11,606")
        XCTAssertEqual(USMoneyFormat.currency(1_394), "$1,394")
        XCTAssertEqual(USMoneyFormat.rpm(2.82), "$2.82")
    }

    func testOlderSnapshotStillDecodes() throws {
        let json = """
        {"target":6000,"gross":3820,"dailyTargetNeeded":545,"daysRemaining":4,"paceStatus":"onTrack","weekLabel":"Aug 3 – Aug 9","updatedAt":"2025-08-06T14:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetGoalSnapshot.self, from: json)
        XCTAssertEqual(snapshot.gross, 3820, accuracy: 0.001)
        XCTAssertEqual(snapshot.remaining, 2_180, accuracy: 0.001)
        XCTAssertEqual(snapshot.progressPercent, 3820 / 6000 * 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.rpm, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.weekRange, "Aug 3 – Aug 9")
    }

    func testRoundTripKeepsTheNewFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(WidgetGoalSnapshot.placeholder)
        let decoded = try decoder.decode(WidgetGoalSnapshot.self, from: data)
        XCTAssertEqual(decoded.weekRange, "18 – 24 окт")
        XCTAssertEqual(decoded.rpm, 2.82, accuracy: 0.001)
        XCTAssertEqual(decoded.remaining, 1_394, accuracy: 0.001)
        XCTAssertEqual(decoded.progressPercent, 89, accuracy: 0.001)
    }

    private func monthName(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLL"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "").lowercased(with: locale)
    }
}

final class WidgetDeepLinkTests: XCTestCase {

    func testWidgetButtonsOpenCameraScannerAndDiesel() {
        XCTAssertEqual(WidgetDeepLink.route(from: WidgetDeepLink.url(for: .camera)), .camera)
        XCTAssertEqual(WidgetDeepLink.route(from: WidgetDeepLink.url(for: .scanner)), .scanner)
        XCTAssertEqual(WidgetDeepLink.route(from: WidgetDeepLink.url(for: .addDiesel)), .addDiesel)
        XCTAssertEqual(WidgetActionOrder.all, [.camera, .scanner, .addDiesel])
    }

    func testAliasesMatchAndroidAndUnknownOpensHome() {
        XCTAssertEqual(WidgetDeepLink.sanitize("attach_pick/camera"), .camera)
        XCTAssertEqual(WidgetDeepLink.sanitize("attach_pick/scanner"), .scanner)
        XCTAssertEqual(WidgetDeepLink.sanitize("diesel"), .addDiesel)
        XCTAssertEqual(WidgetDeepLink.sanitize("stats"), .analytics)
        XCTAssertEqual(WidgetDeepLink.sanitize("weekly_goal"), .weeklyGoal)
        XCTAssertEqual(WidgetDeepLink.sanitize("not-a-screen"), .home)
        XCTAssertNil(WidgetDeepLink.sanitize(nil))
        XCTAssertNil(WidgetDeepLink.sanitize("   "))
        XCTAssertNil(WidgetDeepLink.route(from: URL(string: "https://example.com/camera")!))
        XCTAssertEqual(
            WidgetDeepLink.route(from: URL(string: "truckorig://app/scanner")!),
            .scanner
        )
    }
}

/// The three labeled widget actions, in the order the owner approved.
enum WidgetActionOrder {
    static let all: [WidgetRoute] = [.camera, .scanner, .addDiesel]
}

final class PeriodFinanceTests: XCTestCase {

    func testOnePaycheckPerWeekAndDieselSavings() {
        let week = makeDate(2025, 10, 20)
        let older = PaycheckSlice(amount: 1_000, weekNumber: 43, year: 2025, date: week, updatedAt: week)
        let latest = PaycheckSlice(
            amount: 4_860,
            weekNumber: 43,
            year: 2025,
            date: week,
            updatedAt: week.addingTimeInterval(3600)
        )
        let otherWeek = PaycheckSlice(
            amount: 500,
            weekNumber: 42,
            year: 2025,
            date: makeDate(2025, 10, 10),
            updatedAt: makeDate(2025, 10, 10)
        )
        let fill = DieselSlice(
            gallons: 168,
            totalCost: 612,
            pricePerGallon: 3.88,
            discountPricePerGallon: 3.64,
            date: week
        )
        let finance = PeriodFinanceCalculator.calculate(
            paychecks: [older, latest, otherWeek],
            diesel: [fill],
            range: makeDate(2025, 10, 18)..<makeDate(2025, 10, 25)
        )

        XCTAssertEqual(finance.paycheckTotal, 4_860, accuracy: 0.001)
        XCTAssertEqual(finance.dieselTotal, 612, accuracy: 0.001)
        XCTAssertEqual(finance.dieselGallons, 168, accuracy: 0.001)
        XCTAssertEqual(finance.avgPricePerGallon ?? 0, 612 / 168, accuracy: 0.001)
        XCTAssertEqual(finance.dieselSavings, (3.88 - 3.64) * 168, accuracy: 0.02)
        XCTAssertTrue(finance.hasData)
    }

    func testEmptyFinanceHasNoAveragePrice() {
        let finance = PeriodFinanceCalculator.calculate(paychecks: [], diesel: [])
        XCTAssertFalse(finance.hasData)
        XCTAssertNil(finance.avgPricePerGallon)
    }
}

final class LoadSourceTagTests: XCTestCase {

    func testRelayManualAndBroker() {
        XCTAssertEqual(LoadSourceTag.detect(tripId: "T-1", rawMessage: "Amazon Relay\nTrip ID: T-1"), .relay)
        XCTAssertEqual(LoadSourceTag.detect(tripId: "M-0826-CHI", rawMessage: ""), .manual)
        XCTAssertEqual(LoadSourceTag.detect(tripId: "B-9", rawMessage: "broker rate con"), .broker)
    }
}
