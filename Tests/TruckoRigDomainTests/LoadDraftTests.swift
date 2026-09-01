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
}
