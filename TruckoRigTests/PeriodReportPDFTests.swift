import PDFKit
import XCTest
@testable import TruckoRig

/// The branded PDF is the same report as the plain text: header, summary, then each load.
final class PeriodReportPDFTests: XCTestCase {

    func testPDFCarriesTheReportTextAndStartsANewPage() throws {
        let report = sample(loadCount: 14)
        let data = PeriodReportPDF.data(for: report)

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 2)
        let text = pageText(document)
        XCTAssertTrue(text.contains("Khaidar Safarov"))
        XCTAssertTrue(text.contains("Summary"))
        XCTAssertTrue(text.contains("T-01"))
        XCTAssertTrue(text.contains("T-14"))
        XCTAssertTrue(text.contains("Only on this device"))
        XCTAssertFalse(text.contains("T-OUT"))
        let summary = text.range(of: "Summary")
        let firstLoad = text.range(of: "T-01")
        let lastLoad = text.range(of: "T-14")
        XCTAssertLessThan(summary?.lowerBound ?? text.endIndex, firstLoad?.lowerBound ?? text.startIndex)
        XCTAssertLessThan(firstLoad?.lowerBound ?? text.endIndex, lastLoad?.lowerBound ?? text.startIndex)
    }

    func testEmptyPeriodPDFStillExplainsItself() throws {
        let report = sample(loadCount: 0)
        let data = PeriodReportPDF.data(for: report)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let text = pageText(document)
        XCTAssertTrue(text.contains("No loads in this period."))
        XCTAssertTrue(text.contains("Gross revenue"))
        XCTAssertFalse(text.contains("T-01"))
    }

    private func pageText(_ document: PDFDocument) -> String {
        (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    private func sample(loadCount: Int) -> PeriodReport {
        let zone = TimeZone(identifier: "America/New_York") ?? .current
        let week = TruckingWeek(weekStart: .sunday, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 16
        parts.hour = 12
        let day = calendar.date(from: parts) ?? Date()
        let ref = week.week(for: day)
        let loads = (1...loadCount).map { index in
            PeriodReportLoadInput(
                tripId: String(format: "T-%02d", index),
                rate: 100,
                loadedMiles: 50,
                emptyMiles: 5,
                filedOn: day,
                pickupAt: day,
                deliveryAt: day,
                weekNumber: ref.weekNumber,
                year: ref.year,
                origin: "Dallas, TX",
                destination: "Chicago, IL",
                source: .broker
            )
        }
        let outsider = PeriodReportLoadInput(
            tripId: "T-OUT",
            rate: 5,
            loadedMiles: 1,
            emptyMiles: 0,
            filedOn: day,
            weekNumber: 1,
            year: 2020
        )
        return PeriodReportBuilder.build(
            PeriodReportRequest(
                driverName: "Khaidar Safarov",
                scope: .week(ref),
                loads: loads + [outsider],
                fuel: [PeriodReportFuelFill(totalCost: 40, gallons: 10, date: day)],
                expenses: [PeriodReportExpense(amount: 8, date: day)],
                weeklyGoal: 12_000,
                generatedAt: day,
                language: .english,
                measurementSystem: .miles,
                week: week
            )
        )
    }
}
