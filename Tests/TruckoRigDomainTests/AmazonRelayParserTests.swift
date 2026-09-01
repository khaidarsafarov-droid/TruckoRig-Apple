import XCTest
@testable import TruckoRigDomain

final class AmazonRelayParserTests: XCTestCase {

    private let reference = makeDate(2026, 7, 1, 9, 0)

    func testParsesCanonicalRelayPaste() throws {
        let text = """
        Trip ID: T-116KYL6KW
        Total Rate: 2500.00
        Total Loaded Miles: 850 mi
        Pu-address: SWF2, Garner, NC
        Del-address: TOL3, Perrysburg, OH
        """

        let result = try AmazonRelayParser.parse(text, reference: reference, timeZone: testTimeZone).get()

        XCTAssertEqual(result.tripId, "T-116KYL6KW")
        XCTAssertEqual(result.totalRate, 2500, accuracy: 0.001)
        XCTAssertEqual(result.totalMiles, 850, accuracy: 0.001)
        XCTAssertEqual(result.load.stops.count, 2)
        XCTAssertEqual(result.load.pointA, "Garner, NC")
        XCTAssertEqual(result.load.pointB, "Perrysburg, OH")
        XCTAssertEqual(result.load.stops.first?.facility, "SWF2")
        XCTAssertEqual(result.ratePerMile, 2.94, accuracy: 0.001)
    }

    func testUnicodeTripIdWinsOverPickupNumber() throws {
        let text = """
        𝗧𝗿𝗶𝗽 𝗜𝗗:  T-116P1ZLK1  PU# 1162L65P5 Note: Empty trailer
        Pu-time: 07/03 07:49 CDT
        Pu-address: DAL91400 Southport Parkway
        WILMER, TX 75172
        Del-time: 07/03 09:29 CDT
        Del-address: VENDOR-10122706905600 Mark IV Pky
        FORT WORTH, TX 76131
        Total Rate: $2710.550048828125
        Total Loaded Miles: 1121.81 mi
        """

        let result = try AmazonRelayParser.parse(text, reference: reference, timeZone: testTimeZone).get()

        XCTAssertEqual(result.tripId, "T-116P1ZLK1")
        XCTAssertEqual(result.totalRate, 2710.550048828125, accuracy: 0.001)
        XCTAssertEqual(result.totalMiles, 1121.81, accuracy: 0.001)
        XCTAssertEqual(result.load.puCount, 1)
        XCTAssertEqual(result.load.stops.first?.puNumber, "1162L65P5")
    }

    func testMultiLegTripKeepsEveryStop() throws {
        let text = """
        Trip ID: T-116P1ZLK1
        Total Rate: $2710.55
        Total Loaded Miles: 1121.81 mi
        PU# 1162L65P5 Note: Empty trailer
        Pu-time: 07/03 07:49 CDT
        Pu-address: DAL9, Wilmer, TX
        Del-time: 07/03 09:29 CDT
        Del-address: FTW1, Fort Worth, TX
        PU# 113RDYNXF Note: Preloaded
        Pu-time: 07/03 09:30 CDT
        Pu-address: FTW1, Fort Worth, TX
        Del-time: 07/05 07:00 EDT
        Del-address: XCH2, Garden City, GA
        """

        let result = try AmazonRelayParser.parse(text, reference: reference, timeZone: testTimeZone).get()

        XCTAssertEqual(result.load.puCount, 2)
        XCTAssertEqual(result.load.delCount, 2)
        XCTAssertEqual(result.load.pointA, "Wilmer, TX")
        XCTAssertEqual(result.load.pointB, "Garden City, GA")
        XCTAssertEqual(result.durationDays, 2, accuracy: 0.001)
    }

    func testMessageWithoutTripIdIsRejected() {
        let text = """
        PU# 1162L65P5 Note: Empty trailer
        Pu-address: WILMER, TX 75172
        Del-address: Garden City, GA 31408
        Total Rate: $2710.55
        Total Loaded Miles: 1121.81 mi
        """

        XCTAssertNil(LoadMessageParser.parseOne(text, reference: reference, timeZone: testTimeZone))
        XCTAssertEqual(AmazonRelayParser.diagnose(text), .missingTripId)
    }

    func testZeroRateIsRejectedWithSpecificFailure() {
        let text = """
        Trip ID: T-AAA111
        Total Rate: $0
        Pu-address: SWF2, Garner, NC
        """

        guard case .failure(let failure) = AmazonRelayParser.parse(text, reference: reference, timeZone: testTimeZone) else {
            return XCTFail("Expected a failure for a zero-rate trip")
        }
        XCTAssertEqual(failure, .missingRate)
    }

    func testTripWithoutAddressIsRejected() {
        let text = """
        Trip ID: T-AAA111
        Total Rate: $1200
        Total Loaded Miles: 400 mi
        """

        guard case .failure(let failure) = AmazonRelayParser.parse(text, reference: reference, timeZone: testTimeZone) else {
            return XCTFail("Expected a failure for a trip with no stops")
        }
        XCTAssertEqual(failure, .missingAddress)
    }

    func testNonLoadTextIsRejected() {
        XCTAssertEqual(AmazonRelayParser.diagnose("Hey, are you home this weekend?"), .notLoadLike)
    }

    func testSeveralTripsInOnePasteBecomeSeveralLoads() {
        let text = """
        Trip ID: T-AAA111
        Total Rate: $1000
        Total Loaded Miles: 500 mi
        PU# PU1
        Pu-address: Austin, TX
        Del-address: Dallas, TX

        Trip ID: T-BBB222
        Total Rate: $2000
        Total Loaded Miles: 600 mi
        PU# PU2
        Pu-address: Houston, TX
        Del-address: San Antonio, TX
        """

        let loads = LoadMessageParser.parseAll(text, reference: reference, timeZone: testTimeZone)

        XCTAssertEqual(loads.map(\.tripId), ["T-AAA111", "T-BBB222"])
        XCTAssertEqual(loads[1].totalRate, 2000, accuracy: 0.001)
    }

    func testChatHistoryHeadersPinRelayDatesToTheMessageYear() {
        let history = """
        bruce, [05.07.2025 10:00]
        Trip ID: T-JUL2025
        Total Rate: $1500.00
        Total Loaded Miles: 400 mi
        PU# PU1
        Pu-time: 07/05 08:00 EDT
        Pu-address: SWF2, Garner, NC
        Del-time: 07/06 08:00 EDT
        Del-address: TOL3, Perrysburg, OH

        bruce, [21.08.2025 02:09]
        Trip ID: T-AUG2025
        Total Rate: $1197.76
        Total Loaded Miles: 425 mi
        PU# PU2
        Pu-time: 08/21 01:39 EDT
        Pu-address: MDT5, Lewisberry, PA
        Del-time: 08/21 03:32 EDT
        Del-address: VENDOR-1, York, PA
        """

        // Pasted in 2026: without the chat headers both trips would be filed under 2026.
        let loads = LoadMessageParser.parseAll(history, reference: makeDate(2026, 8, 21, 16, 0), timeZone: testTimeZone)

        XCTAssertEqual(loads.count, 2)
        let july = loads.first { $0.tripId == "T-JUL2025" }
        let august = loads.first { $0.tripId == "T-AUG2025" }
        XCTAssertEqual(july?.stops.first?.localDay, "2025-07-05")
        XCTAssertEqual(august?.stops.first?.localDay, "2025-08-21")
        XCTAssertEqual(isoDay(july?.date), "2025-07-05")
    }

    func testScheduleUsesPrintedTimezone() throws {
        let text = """
        Trip ID: T-TZ1
        Total Rate: $1000
        Pu-time: 07/06 08:00 PDT
        Pu-address: ONT8, Ontario, CA
        Del-time: 07/06 20:00 EDT
        Del-address: EWR4, Newark, NJ
        """

        let result = try AmazonRelayParser.parse(text, reference: reference, timeZone: testTimeZone).get()
        let pickup = try XCTUnwrap(result.load.pickups.first)
        let delivery = try XCTUnwrap(result.load.deliveries.first)

        XCTAssertEqual(pickup.timezone, "PDT")
        // 08:00 PDT is 11:00 EDT, so the same-day delivery at 20:00 EDT is nine hours later.
        let hours = try XCTUnwrap(delivery.scheduledTime).timeIntervalSince(try XCTUnwrap(pickup.scheduledTime)) / 3600
        XCTAssertEqual(hours, 9, accuracy: 0.001)
        XCTAssertEqual(pickup.localDay, "2026-07-06")
    }

    func testDurationSpansIntoTheNewYear() throws {
        let text = """
        Trip ID: T-NYE
        Total Rate: $3000
        Total Loaded Miles: 1200 mi
        Pu-time: 12/30 08:00 EST
        Pu-address: SWF2, Garner, NC
        Del-time: 01/02 08:00 EST
        Del-address: TOL3, Perrysburg, OH
        """

        let result = try AmazonRelayParser.parse(text, reference: makeDate(2025, 12, 30, 7, 0), timeZone: testTimeZone).get()

        XCTAssertEqual(result.load.pickups.first?.localDay, "2025-12-30")
        XCTAssertEqual(result.load.deliveries.first?.localDay, "2026-01-02")
        XCTAssertEqual(result.durationDays, 3, accuracy: 0.001)
    }
}
