import XCTest
@testable import TruckoRigDomain

final class ShareLoadClassifierTests: XCTestCase {

    private let reference = Date(timeIntervalSince1970: 1_767_225_600)

    func testRateConfirmationIsALoad() {
        let verdict = ShareLoadClassifier.classify(text: rateConfirmation, fileName: "rate-confirmation.pdf", reference: reference)
        guard case .accepted(let loads) = verdict else {
            return XCTFail("expected a load, got \(verdict)")
        }
        XCTAssertEqual(loads.count, 1)
        let load = loads[0]
        XCTAssertEqual(load.tripId, "NW-44921")
        XCTAssertEqual(load.broker, "Northwind Logistics")
        XCTAssertEqual(load.origin, "Dallas, TX 75201")
        XCTAssertEqual(load.destination, "Atlanta, GA 30301")
        XCTAssertEqual(load.rate, 2450, accuracy: 0.001)
        XCTAssertEqual(load.miles, 780, accuracy: 0.001)
        XCTAssertTrue(load.missing.isEmpty)
        XCTAssertGreaterThanOrEqual(load.score, ShareLoadClassifier.acceptScore)
        XCTAssertEqual(day(load.pickupDate), "2026-03-12")
        XCTAssertEqual(day(load.deliveryDate), "2026-03-14")
    }

    func testRelayPasteIsALoad() {
        let text = """
        Trip ID: T-116KYL6KW
        Total Rate: 2500.00
        Total Loaded Miles: 850 mi
        Pu-address: SWF2, Garner, NC
        Del-address: TOL3, Perrysburg, OH
        """
        let verdict = ShareLoadClassifier.classify(text: text, reference: reference)
        guard case .accepted(let loads) = verdict else {
            return XCTFail("expected a relay load, got \(verdict)")
        }
        XCTAssertEqual(loads.first?.tripId, "T-116KYL6KW")
        XCTAssertEqual(loads.first?.rate ?? 0, 2500, accuracy: 0.001)
        XCTAssertFalse(loads.first?.origin.isEmpty ?? true)
        XCTAssertFalse(loads.first?.destination.isEmpty ?? true)
    }

    func testPartialRateConIsAddedWithMissingFields() {
        let text = """
        Rate Confirmation
        Rate: $1,800.00
        Pickup: Columbus, OH
        Delivery: Chicago, IL
        """
        let verdict = ShareLoadClassifier.classify(text: text, reference: reference)
        guard case .accepted(let loads) = verdict else {
            return XCTFail("expected a partial load, got \(verdict)")
        }
        let load = loads[0]
        XCTAssertEqual(load.rate, 1800, accuracy: 0.001)
        XCTAssertEqual(load.origin, "Columbus, OH")
        XCTAssertEqual(load.destination, "Chicago, IL")
        XCTAssertTrue(load.missing.contains(.miles))
        XCTAssertTrue(load.missing.contains(.broker))
        XCTAssertTrue(load.missing.contains(.pickupDate))
        XCTAssertTrue(load.missing.contains(.tripId))
        XCTAssertTrue(load.tripId.hasPrefix("S-"))
    }

    func testOneCityWithLoadNumberStillAdds() {
        let text = """
        Load # AB12CD
        Rate: $2,000.00
        Pickup: Denver, CO
        Pickup Date: 04/02/2026
        Miles: 400
        """
        let verdict = ShareLoadClassifier.classify(text: text, reference: reference)
        guard case .accepted(let loads) = verdict else {
            return XCTFail("expected a partial load, got \(verdict)")
        }
        XCTAssertEqual(loads[0].tripId, "AB12CD")
        XCTAssertTrue(loads[0].missing.contains(.destination))
        XCTAssertFalse(loads[0].missing.contains(.miles))
    }

    func testCitiesWithoutARateAreNotALoad() {
        let text = """
        Pickup: Denver, CO
        Delivery: Chicago, IL
        See you Monday.
        """
        expectRejection(text)
    }

    func testBareRateIsNotALoad() {
        expectRejection("Rate: $500\nThanks")
    }

    func testChatIsNotALoad() {
        expectRejection("Hey, are you free for lunch tomorrow? The diner on 5th is good.")
    }

    func testDieselReceiptIsNotALoad() {
        let text = """
        Pilot Travel Center
        Diesel 112.4 gallons
        Total $489.22
        Dallas, TX
        Thank you
        """
        expectRejection(text, fileName: "fuel-receipt.jpg")
    }

    func testPaycheckIsNotALoad() {
        let text = """
        Driver Settlement
        Net Pay $2,140.00
        Gross Pay $3,000.00
        Week Start 03/01/2026
        """
        expectRejection(text, fileName: "settlement.pdf")
    }

    func testWebLinkIsNotALoad() {
        expectRejection("https://example.com/inbox/message/42")
    }

    func testSecondLoadInTheSameNewFileIsKept() {
        let first = ShareImportFingerprint(tripId: "NW-1", broker: "Acme", fileSHA256: "abc")
        let second = ShareImportFingerprint(tripId: "NW-2", broker: "Acme", fileSHA256: "abc")
        XCTAssertFalse(ShareImportDeduper.isDuplicate(second, saved: [], batch: [first]))
    }

    func testRepeatedFileIsADuplicateOfASavedLoad() {
        let saved = [ShareImportFingerprint(tripId: "NW-1", broker: "Acme", fileSHA256: "abc")]
        let again = ShareImportFingerprint(tripId: "NW-2", broker: "Acme", fileSHA256: "ABC")
        XCTAssertTrue(ShareImportDeduper.isDuplicate(again, saved: saved, batch: []))
    }

    func testSameFileHashIsADuplicate() {
        let candidate = ShareImportFingerprint(tripId: "NW-1", broker: "Acme", fileSHA256: "abc")
        let existing = [ShareImportFingerprint(tripId: "OTHER", broker: "Other", fileSHA256: "ABC")]
        XCTAssertTrue(ShareImportDeduper.isDuplicate(candidate, among: existing))
    }

    func testSameLoadNumberAndBrokerIsADuplicate() {
        let candidate = ShareImportFingerprint(tripId: "nw-44921", broker: "Northwind Logistics", fileSHA256: nil)
        let existing = [ShareImportFingerprint(tripId: "NW-44921", broker: "northwind logistics", fileSHA256: nil)]
        XCTAssertTrue(ShareImportDeduper.isDuplicate(candidate, among: existing))
    }

    func testSameLoadNumberDifferentBrokerIsKept() {
        let candidate = ShareImportFingerprint(tripId: "48291", broker: "TQL", fileSHA256: nil)
        let existing = [ShareImportFingerprint(tripId: "48291", broker: "Acme Freight", fileSHA256: nil)]
        XCTAssertFalse(ShareImportDeduper.isDuplicate(candidate, among: existing))
    }

    func testBlankBrokerMatchesAnExistingLoadNumber() {
        let candidate = ShareImportFingerprint(tripId: "48291", broker: "", fileSHA256: nil)
        let existing = [ShareImportFingerprint(tripId: "48291", broker: "Acme Freight", fileSHA256: nil)]
        XCTAssertTrue(ShareImportDeduper.isDuplicate(candidate, among: existing))
    }

    func testCommitDisambiguatesStorageIdAndKeepsLogicalNumber() {
        let fields = ShareLoadFields(
            tripId: "48291",
            broker: "TQL",
            origin: "Dallas, TX",
            destination: "Atlanta, GA",
            pickupDate: nil,
            deliveryDate: nil,
            rate: 900,
            miles: 0,
            missing: [.miles],
            score: 70
        )
        let plan = ShareLoadCommit.plan(
            fields: fields,
            fileSHA256: "deadbeef",
            sourceText: "demo",
            existing: [ShareImportFingerprint(tripId: "48291", broker: "Acme", fileSHA256: nil)],
            takenStorageIds: ["48291"]
        )
        guard case .insert(let draft) = plan else {
            return XCTFail("expected an insert")
        }
        XCTAssertEqual(draft.tripId, "48291-TQL")
        XCTAssertEqual(draft.totalRate, 900, accuracy: 0.001)
        XCTAssertEqual(draft.pointA, "Dallas, TX")
        XCTAssertEqual(draft.pointB, "Atlanta, GA")
        let recovered = ShareImportNote.fingerprint(storageTripId: draft.tripId, rawMessage: draft.rawMessage)
        XCTAssertEqual(recovered.tripId, "48291")
        XCTAssertEqual(recovered.broker, "TQL")
        XCTAssertEqual(recovered.fileSHA256, "deadbeef")
    }

    func testCommitRejectsADuplicateBeforeInsert() {
        let fields = ShareLoadFields(
            tripId: "48291",
            broker: "Acme",
            origin: "Dallas, TX",
            destination: "Atlanta, GA",
            pickupDate: nil,
            deliveryDate: nil,
            rate: 900,
            miles: 10,
            missing: [],
            score: 80
        )
        let plan = ShareLoadCommit.plan(
            fields: fields,
            fileSHA256: nil,
            sourceText: "demo",
            existing: [ShareImportFingerprint(tripId: "48291", broker: "Acme", fileSHA256: nil)],
            takenStorageIds: ["48291"]
        )
        guard case .duplicate = plan else {
            return XCTFail("expected a duplicate")
        }
    }

    func testInboxRoundTripKeepsTheFileAndThenDeletesIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = ShareImportInbox(root: root.appendingPathComponent("inbox", isDirectory: true))
        let source = root.appendingPathComponent("outside.txt")
        try Data("demo rate con".utf8).write(to: source)
        let fields = ShareLoadFields(
            tripId: "NW-1",
            broker: "Northwind",
            origin: "Dallas, TX",
            destination: "Atlanta, GA",
            pickupDate: nil,
            deliveryDate: nil,
            rate: 1000,
            miles: 100,
            missing: [],
            score: 80
        )
        let record = ShareImportRecord(sourceText: "demo rate con", originalFileName: "rate.txt", load: fields)
        let stored = try inbox.enqueue(record, file: source)
        let pending = try inbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id, record.id)
        XCTAssertEqual(pending[0].load.tripId, "NW-1")
        let file = try XCTUnwrap(inbox.fileURL(for: stored))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "demo rate con")
        try inbox.remove(record.id)
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertNil(inbox.fileURL(for: stored))
    }

    private func expectRejection(_ text: String, fileName: String? = nil) {
        let verdict = ShareLoadClassifier.classify(text: text, fileName: fileName, reference: reference)
        guard case .rejected = verdict else {
            return XCTFail("expected a rejection, got \(verdict)")
        }
    }

    private func day(_ date: Date?) -> String {
        guard let date else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private let rateConfirmation = """
    RATE CONFIRMATION
    Broker: Northwind Logistics
    MC# 654321
    Load # NW-44921
    Carrier: Demo Hauling LLC

    Shipper
    100 Demo Street
    Dallas, TX 75201
    Pickup Date: 03/12/2026

    Consignee
    200 Sample Avenue
    Atlanta, GA 30301
    Delivery Date: 03/14/2026

    Rate: $2,450.00
    Miles: 780
    """
}
