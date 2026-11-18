import XCTest
@testable import TruckoRigDomain

final class LoadDraftTests: XCTestCase {

    private func draft() -> LoadDraft {
        LoadDraft(
            tripId: "T-116KYL6KW",
            date: makeDate(2025, 8, 4),
            totalRate: 2500,
            totalMiles: 850,
            stops: [
                StopDraft(type: .pickup, city: "Garner", state: "NC", scheduledTime: makeDate(2025, 8, 4, 8, 0)),
                StopDraft(type: .delivery, city: "Perrysburg", state: "OH", scheduledTime: makeDate(2025, 8, 5, 8, 0)),
            ]
        )
    }

    func testCompleteDraftIsValid() {
        let draft = draft()

        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.pointA, "Garner, NC")
        XCTAssertEqual(draft.pointB, "Perrysburg, OH")
        XCTAssertEqual(draft.ratePerMile, 2.94, accuracy: 0.001)
    }

    func testMissingTripIdIsRejected() {
        var draft = draft()
        draft.tripId = "  "

        XCTAssertEqual(draft.validationErrors, [.missingTripId])
    }

    func testZeroRateIsRejected() {
        var draft = draft()
        draft.totalRate = 0

        XCTAssertEqual(draft.validationErrors, [.nonPositiveRate])
    }

    func testFinishBeforeFirstPickupIsRejected() {
        var draft = draft()
        draft.actualFinishDate = makeDate(2025, 8, 3)

        XCTAssertEqual(draft.validationErrors, [.finishBeforeStart])
    }

    func testFinishAfterPickupIsAccepted() {
        var draft = draft()
        draft.actualFinishDate = makeDate(2025, 8, 6)

        XCTAssertTrue(draft.isValid)
    }

    func testStopsAreRenumberedInOrder() {
        var draft = draft()
        draft.stops.append(StopDraft(type: .delivery, city: "Toledo", state: "OH"))

        XCTAssertEqual(draft.normalizedStops.map(\.stopNumber), [1, 2, 3])
    }

    func testRenumberStopsAfterDeleteKeepsOrder() {
        var draft = draft()
        draft.stops.append(StopDraft(type: .delivery, stopNumber: 9, city: "Toledo", state: "OH"))
        draft.stops.remove(at: 1)
        draft.renumberStops()

        XCTAssertEqual(draft.stops.map(\.stopNumber), [1, 2])
        XCTAssertEqual(draft.stops.map(\.city), ["Garner", "Toledo"])
    }

    func testDraftFromParsedLoadCarriesEverythingOver() throws {
        let text = """
        Trip ID: T-116KYL6KW
        Total Rate: 2500.00
        Total Loaded Miles: 850 mi
        Pu-address: SWF2, Garner, NC
        Del-address: TOL3, Perrysburg, OH
        """
        let parsed = try XCTUnwrap(
            LoadMessageParser.parseOne(text, reference: makeDate(2025, 8, 4), timeZone: testTimeZone)
        )

        let draft = LoadDraft(parsed: parsed)

        XCTAssertEqual(draft.tripId, "T-116KYL6KW")
        XCTAssertEqual(draft.totalRate, 2500, accuracy: 0.001)
        XCTAssertEqual(draft.stops.count, 2)
        XCTAssertEqual(draft.rawMessage, text)
        XCTAssertTrue(draft.isValid)
    }

    func testMoneyFieldShowsCentsNotADebugDescription() {
        let locale = Locale(identifier: "en_US_POSIX")
        let cases: [(Double, String)] = [
            (2111.72, "2111.72"),
            (0.05, "0.05"),
            (1_000_000, "1000000.00"),
            (0.10, "0.10"),
            (10, "10.00"),
        ]
        for (amount, expected) in cases {
            let text = MoneyFieldText.prefill(dollars: amount, locale: locale)
            XCTAssertEqual(text, expected, "prefill \(amount)")
            XCTAssertFalse(text.contains("Money"))
            XCTAssertFalse(text.contains("cents"))
            let back = MoneyFieldText.commit(text: text, original: amount, locale: locale)
            XCTAssertEqual(back, amount)
            XCTAssertEqual(MoneyCents.fromDollars(back).cents, MoneyCents.fromDollars(amount).cents)
        }
    }

    func testMoneyFieldUsesTheLocaleDecimalSeparator() {
        let locale = Locale(identifier: "ru_RU")
        let text = MoneyFieldText.prefill(dollars: 2111.72, locale: locale)
        let separator = locale.decimalSeparator ?? "."
        XCTAssertEqual(text, "2111\(separator)72")
        XCTAssertFalse(text.contains("cents"))
        XCTAssertEqual(
            MoneyFieldText.commit(text: text, original: 2111.72, locale: locale),
            2111.72
        )
        XCTAssertEqual(
            MoneyFieldText.prefill(dollars: 1_000_000, locale: locale),
            "1000000\(separator)00"
        )
    }

    func testAndroidDebugMoneyTextIsNotARate() {
        let poisoned = "Money(cents=211172)"
        XCTAssertNotEqual(MoneyFieldText.prefill(dollars: 2111.72), poisoned)
        XCTAssertEqual(NumberParsing.parseMoney(poisoned), 0)
        var draft = untouchedLoad()
        draft.totalRate = NumberParsing.parseMoney(poisoned)
        XCTAssertFalse(draft.isValid)
        XCTAssertEqual(draft.validationErrors, [.nonPositiveRate])
    }

    func testUntouchedEditFormRoundTripsEveryField() {
        let original = untouchedLoad()
        let saved = original.savingUntouchedForm()

        XCTAssertEqual(saved, original)
        XCTAssertEqual(saved.totalRate, 2111.72)
        XCTAssertEqual(saved.disputeAmount, 0.05)
        XCTAssertEqual(saved.totalMiles, 714.5)
        XCTAssertEqual(saved.deadheadMiles, 45)
        XCTAssertEqual(saved.date, original.date)
        XCTAssertEqual(saved.actualFinishDate, original.actualFinishDate)
        XCTAssertEqual(saved.stops, original.stops)
        XCTAssertEqual(saved.rawMessage, original.rawMessage)
        XCTAssertTrue(saved.isValid)
    }

    func testUntouchedEditFormRoundTripsWithACommaLocale() {
        let locale = Locale(identifier: "fr_FR")
        let original = untouchedLoad()
        XCTAssertEqual(original.savingUntouchedForm(locale: locale), original)
    }

    func testEditedRateCommitsTheNewCents() {
        let next = MoneyFieldText.commit(text: "2111.73", original: 2111.72)
        XCTAssertEqual(MoneyCents.fromDollars(next).cents, 211_173)
    }

    private func untouchedLoad() -> LoadDraft {
        LoadDraft(
            tripId: "T-111HLM7BD",
            date: makeDate(2026, 10, 29, 6, 30),
            totalRate: 2111.72,
            totalMiles: 714.5,
            stops: [
                StopDraft(
                    type: .pickup,
                    stopNumber: 1,
                    note: "dock 4",
                    facility: "ATL2",
                    city: "Atlanta",
                    state: "GA",
                    scheduledTime: makeDate(2026, 10, 29, 6, 30)
                ),
                StopDraft(
                    type: .delivery,
                    stopNumber: 2,
                    note: "receiver closed at 15:00",
                    facility: "ABE8",
                    city: "Carlisle",
                    state: "PA",
                    scheduledTime: makeDate(2026, 10, 30, 14, 0)
                ),
            ],
            actualFinishDate: makeDate(2026, 10, 30, 15, 0),
            isDispute: true,
            disputeCompleted: false,
            disputeResponseDate: makeDate(2026, 11, 2),
            disputeAmount: 0.05,
            disputeApplyToLoad: false,
            equipmentType: "DRY_VAN",
            deadheadMiles: 45,
            rawMessage: "Trip ID: T-111HLM7BD\nTotal Rate: 2111.72"
        )
    }
}
