import XCTest
@testable import TruckoRigDomain

final class NumberParsingTests: XCTestCase {

    func testMoneyFormats() {
        XCTAssertEqual(NumberParsing.parseMoney("2500"), 2500, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.parseMoney("$2,500.00"), 2500, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.parseMoney("2710.550048828125"), 2710.550048828125, accuracy: 0.000001)
        XCTAssertEqual(NumberParsing.parseMoney("1 234,56"), 1234.56, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.parseMoney(nil), 0, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.parseMoney("n/a"), 0, accuracy: 0.001)
    }

    func testEuropeanDecimalCommaIsNotThousandsSeparator() {
        XCTAssertEqual(NumberParsing.parseMoney("2500,50"), 2500.50, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.parseMoney("2,500"), 2500, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.parseMoney("1.234,56"), 1234.56, accuracy: 0.001)
    }

    func testMiles() {
        XCTAssertEqual(NumberParsing.parseMiles("1,121.81 mi"), 1121.81, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.parseMiles("850"), 850, accuracy: 0.001)
    }

    func testDroppedDecimalInLoadedMilesIsRepaired() {
        // Relay exported 1827.81 mi as 182781, which would report RPM near $0.01.
        XCTAssertEqual(NumberParsing.sanitizeLoadedMiles(182781, totalRate: 3200), 1827.81, accuracy: 0.001)
    }

    func testPlausibleLongHaulIsLeftAlone() {
        XCTAssertEqual(NumberParsing.sanitizeLoadedMiles(2400, totalRate: 4800), 2400, accuracy: 0.001)
        XCTAssertEqual(NumberParsing.sanitizeLoadedMiles(12000, totalRate: 30000), 12000, accuracy: 0.001)
    }

    func testTripIdNormalization() {
        XCTAssertEqual(TripID.normalize("  t-116kyl6kw "), "T-116KYL6KW")
        XCTAssertTrue(TripID.matches("t-abc123456", "T-ABC123456"))
        XCTAssertFalse(TripID.isValid("   "))
    }
}
