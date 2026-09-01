import XCTest
@testable import TruckoRigDomain

final class CSVExportParserTests: XCTestCase {

    private let records = [
        LoadCSVRecord(
            tripId: "T-116KYL6KW",
            date: "2025-08-04",
            pointA: "Garner, NC",
            pointB: "Perrysburg, OH",
            totalRate: 2500,
            totalMiles: 850,
            stopCount: 2,
            weekNumber: 32,
            year: 2025
        ),
        LoadCSVRecord(
            tripId: "T-AAA111",
            date: "2025-08-05",
            pointA: "Austin, TX",
            pointB: "Dallas, TX",
            totalRate: 1000,
            totalMiles: 500,
            stopCount: 2,
            weekNumber: 32,
            year: 2025
        ),
    ]

    func testRoundTrip() {
        let parsed = CSVExportParser.parse(CSVExportParser.csv(from: records))

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].tripId, "T-116KYL6KW")
        XCTAssertEqual(parsed[0].pointB, "Perrysburg, OH")
        XCTAssertEqual(parsed[0].totalRate, 2500, accuracy: 0.001)
        XCTAssertEqual(parsed[1].totalMiles, 500, accuracy: 0.001)
        XCTAssertEqual(parsed[0].weekNumber, 32)
    }

    func testQuotedCommasSurviveExport() {
        let csv = CSVExportParser.csv(from: records)
        let header = csv.split(separator: "\n").first.map(String.init)

        XCTAssertEqual(header, CSVExportParser.header.joined(separator: ","))
        XCTAssertTrue(csv.contains("\"Garner, NC\""))
    }

    func testReorderedAndAliasedHeadersStillImport() {
        let csv = """
        Miles,Trip ID,Rate,Date,From,To
        500,t-zzz999,"$1,250.50",2025-08-06,"Houston, TX","Laredo, TX"
        """

        let parsed = CSVExportParser.parse(csv)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].tripId, "T-ZZZ999")
        XCTAssertEqual(parsed[0].totalRate, 1250.50, accuracy: 0.001)
        XCTAssertEqual(parsed[0].totalMiles, 500, accuracy: 0.001)
        XCTAssertEqual(parsed[0].pointA, "Houston, TX")
    }

    func testRowsWithoutTripIdAreSkipped() {
        let csv = """
        trip_id,date,total_rate
        ,2025-08-06,100

        T-OK1,2025-08-07,200
        """

        let parsed = CSVExportParser.parse(csv)

        XCTAssertEqual(parsed.map(\.tripId), ["T-OK1"])
    }

    func testEmbeddedQuotesAreUnescaped() {
        let csv = "trip_id,point_a\nT-Q1,\"He said \"\"go\"\", then left\"\n"

        let parsed = CSVExportParser.parse(csv)

        XCTAssertEqual(parsed[0].pointA, "He said \"go\", then left")
    }
}
