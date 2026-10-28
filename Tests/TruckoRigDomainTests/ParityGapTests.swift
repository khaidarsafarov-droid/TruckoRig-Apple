import XCTest
@testable import TruckoRigDomain

final class ParityGapTests: XCTestCase {

    func testPerDiemUsesTheFiledDateWhenPickupStopsAreMissing() {
        let summary = LoadSummary(
            tripId: "T-1",
            totalRate: 1000,
            totalMiles: 400,
            filedOn: makeDate(2025, 8, 4)
        )
        let days = LoadYieldCalculator.coveredISODates(
            loads: [summary],
            through: makeDate(2025, 8, 4),
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertFalse(days.isEmpty)
    }

    func testJsonLoadBeatsAWeakFlexibleMatch() {
        let json = """
        {"tripId":"T-JSON1","totalRate":1800,"totalMiles":600,"origin":"Garner, NC","destination":"Dallas, TX"}
        """
        let loads = InboundLoadParser.parseAll(json, reference: makeDate(2025, 8, 4))
        XCTAssertEqual(loads.first?.tripId, "T-JSON1")
        XCTAssertEqual(loads.first?.totalRate ?? 0, 1800, accuracy: 0.01)
    }

    func testRelayStillWinsWhenBothParsersSeeARate() {
        let text = """
        Trip ID: T-116KYL6KW
        Total Rate: 2500.00
        Total Loaded Miles: 850 mi
        Pu-address: SWF2, Garner, NC
        Del-address: TOL3, Perrysburg, OH
        """
        let loads = InboundLoadParser.parseAll(text, reference: makeDate(2025, 8, 4))
        XCTAssertEqual(loads.first?.tripId, "T-116KYL6KW")
    }

    func testDay7SurveyWaitsSevenDays() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let record = Day7SurveyPolicy.Record(firstLaunchAt: start)
        XCTAssertFalse(Day7SurveyPolicy.shouldShow(record, now: start.addingTimeInterval(3 * 86400), premiumActive: false))
        XCTAssertTrue(Day7SurveyPolicy.shouldShow(record, now: start.addingTimeInterval(8 * 86400), premiumActive: false))
        XCTAssertFalse(Day7SurveyPolicy.shouldShow(record, now: start.addingTimeInterval(8 * 86400), premiumActive: true))
    }

    func testDistanceUnitRoundTripsInBackupSettings() throws {
        let settings = BackupAppSettings(distanceUnit: "km", dieselWeekStartDay: 2, loadWeekStartDay: 1)
        let data = BackupData(schemaVersion: 2, version: 2, appSettings: settings)
        let decoded = try BackupDataCodec.decode(BackupDataCodec.encode(data))
        XCTAssertEqual(decoded.appSettings?.distanceUnit, "km")
        XCTAssertEqual(decoded.appSettings?.dieselWeekStartDay, 2)
    }
}
