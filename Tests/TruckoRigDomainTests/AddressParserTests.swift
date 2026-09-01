import XCTest
@testable import TruckoRigDomain

final class AddressParserTests: XCTestCase {

    func testRelayOneLinerSplitsFacilityCityState() {
        let parts = AddressParser.parseLine("SWF2, Garner, NC")

        XCTAssertEqual(parts.facility, "SWF2")
        XCTAssertEqual(parts.city, "Garner")
        XCTAssertEqual(parts.state, "NC")
        XCTAssertEqual(parts.zip, "")
    }

    func testRelayOneLinerKeepsZip() {
        let parts = AddressParser.parseLine("TOL3, Perrysburg, OH 43551")

        XCTAssertEqual(parts.facility, "TOL3")
        XCTAssertEqual(parts.city, "Perrysburg")
        XCTAssertEqual(parts.state, "OH")
        XCTAssertEqual(parts.zip, "43551")
    }

    func testPlainCityStateIsNotReadAsFacility() {
        let parts = AddressParser.parseLine("Garner, NC")

        XCTAssertNil(parts.facility)
        XCTAssertEqual(parts.city, "Garner")
        XCTAssertEqual(parts.state, "NC")
    }

    func testFullStateNameIsNormalizedToCode() {
        let parts = AddressParser.parseLine("PERRYSBURG, Ohio 43551")

        XCTAssertEqual(parts.city, "PERRYSBURG")
        XCTAssertEqual(parts.state, "OH")
        XCTAssertEqual(parts.zip, "43551")
    }

    func testMultiLineBlockSeparatesFacilityStreetAndCity() {
        let parts = AddressParser.parseLines([
            "DAL9",
            "1400 Southport Parkway",
            "WILMER, TX 75172",
        ])

        XCTAssertEqual(parts.facility, "DAL9")
        XCTAssertEqual(parts.city, "WILMER")
        XCTAssertEqual(parts.state, "TX")
        XCTAssertEqual(parts.zip, "75172")
        XCTAssertEqual(parts.fullAddress, "DAL9, 1400 Southport Parkway, WILMER, TX 75172")
    }

    func testSlashDelimitedAddress() {
        let parts = AddressParser.parseLine("SWF2 / 100 Main St / Garner, NC 27529")

        XCTAssertEqual(parts.facility, "SWF2")
        XCTAssertEqual(parts.city, "Garner")
        XCTAssertEqual(parts.state, "NC")
        XCTAssertEqual(parts.zip, "27529")
    }

    func testUnparseableLineKeepsTextAsCity() {
        let parts = AddressParser.parseLine("Somewhere off the interstate")

        XCTAssertEqual(parts.city, "Somewhere off the interstate")
        XCTAssertEqual(parts.state, "")
    }

    func testStateNormalization() {
        XCTAssertEqual(USStates.normalize("north carolina"), "NC")
        XCTAssertEqual(USStates.normalize("nc"), "NC")
        XCTAssertEqual(USStates.normalize("Ontario"), "ONTARIO")
        XCTAssertEqual(USStates.name(code: "TX"), "Texas")
        XCTAssertNotNil(USStates.info(code: "dc"))
    }
}
