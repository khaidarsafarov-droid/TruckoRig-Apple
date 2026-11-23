import PDFKit
import XCTest
@testable import TruckoRig

/// US Letter statement: load table first, summary after, header row on every page.
final class PeriodReportPDFTests: XCTestCase {

    func testPDFCarriesTheReportTextAndStartsANewPage() throws {
        let report = sample(loadCount: 48)
        let data = PeriodReportPDF.data(for: report)

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 2)
        let first = document.page(at: 0)
        let box = try XCTUnwrap(first).bounds(for: .mediaBox)
        XCTAssertEqual(box.width, 612, accuracy: 0.5)
        XCTAssertEqual(box.height, 792, accuracy: 0.5)
        let text = pageText(document)
        XCTAssertTrue(text.contains("Alex Rivera"))
        XCTAssertTrue(text.contains("Load Report"))
        XCTAssertTrue(text.contains("Load #"))
        XCTAssertTrue(text.contains("Origin"))
        XCTAssertTrue(text.contains("T-01"))
        XCTAssertTrue(text.contains("T-48"))
        XCTAssertTrue(text.contains("Loads total"))
        XCTAssertTrue(text.contains("Only on this device"))
        XCTAssertFalse(text.contains("T-OUT"))
        XCTAssertFalse(text.contains("Fuel"))
        XCTAssertFalse(text.contains("Expenses"))
        XCTAssertFalse(text.contains("Deductions"))
        XCTAssertFalse(text.contains("IFTA"))
        let firstLoad = text.range(of: "T-01")
        let summary = text.range(of: "Loads total")
        XCTAssertLessThan(firstLoad?.lowerBound ?? text.endIndex, summary?.lowerBound ?? text.startIndex)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("Load #") == true)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("Load #") == true)
    }

    func testHomeFilterMapsOntoTheSharePeriod() {
        XCTAssertEqual(PeriodReportShare.homePeriod(for: .thisWeek), .thisWeek)
        XCTAssertEqual(PeriodReportShare.homePeriod(for: .lastWeek), .lastWeek)
        XCTAssertEqual(PeriodReportShare.homePeriod(for: .calendarWeek), .chosenWeek)
        XCTAssertEqual(PeriodReportShare.homePeriod(for: .thisMonth), .thisMonth)
        for filter in [JournalViewModel.Filter.all, .today, .disputes, .unfinished, .yesterday, .onDate, .dateRange] {
            XCTAssertEqual(PeriodReportShare.homePeriod(for: filter), .other)
        }
    }

    func testEmptyPeriodPDFStillExplainsItself() throws {
        let report = sample(loadCount: 0)
        let data = PeriodReportPDF.data(for: report)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let text = pageText(document)
        XCTAssertTrue(text.contains("No loads in this period."))
        XCTAssertTrue(text.contains("Load Report"))
        XCTAssertTrue(text.contains("Gross total"))
        XCTAssertFalse(text.contains("T-01"))
        XCTAssertFalse(text.contains("Fuel"))
        XCTAssertFalse(text.contains("Deductions"))
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
        let loads = (0..<loadCount).map { offset in
            let index = offset + 1
            return PeriodReportLoadInput(
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
                driverName: "Alex Rivera",
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
