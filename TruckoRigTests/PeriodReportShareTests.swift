import PDFKit
import UIKit
import XCTest
@testable import TruckoRig

/// The home-screen share path writes a PDF file or a text payload, and a failed write has a message.
@MainActor
final class PeriodReportShareTests: XCTestCase {

    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
        super.tearDown()
    }

    func testActivityWritesAPDFFileForAWeek() throws {
        let report = weekReport()
        let directory = try temporaryDirectory()
        let payload = try PeriodReportShare.activity(for: report, format: .pdf, directory: directory)
        let item = try XCTUnwrap(payload.items.first as? PeriodReportActivityItem)
        let sheet = UIActivityViewController(activityItems: payload.items, applicationActivities: nil)
        let placeholder = item.activityViewControllerPlaceholderItem(sheet)
        let url = try XCTUnwrap(placeholder as? URL)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(url.lastPathComponent, "\(report.fileStem).pdf")
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = pageText(document)
        XCTAssertTrue(text.contains("Alex Rivera"))
        XCTAssertTrue(text.contains("T-01"))
        XCTAssertTrue(text.contains("Load Report"))
        let subject = item.activityViewController(sheet, subjectForActivityType: nil)
        XCTAssertFalse(subject.isEmpty)
    }

    func testActivityBuildsATextPayloadForTheSameReport() throws {
        let report = weekReport()
        let payload = try PeriodReportShare.activity(for: report, format: .text)
        let item = try XCTUnwrap(payload.items.first as? PeriodReportActivityItem)
        let sheet = UIActivityViewController(activityItems: payload.items, applicationActivities: nil)
        let placeholder = try XCTUnwrap(item.activityViewControllerPlaceholderItem(sheet) as? String)
        XCTAssertTrue(placeholder.contains("Alex Rivera"))
        XCTAssertTrue(placeholder.contains("T-01"))
        XCTAssertTrue(placeholder.contains(report.periodTitle))
        let subject = item.activityViewController(sheet, subjectForActivityType: nil)
        XCTAssertTrue(subject.contains(report.brand))
        XCTAssertTrue(subject.contains(report.periodTitle))
    }

    /// `JournalView.presentShare` assigns `error.localizedDescription` when `activity` throws.
    func testActivityWriteFailureSurfacesALocalizedMessage() throws {
        let report = weekReport()
        let blocker = try temporaryDirectory().appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        XCTAssertThrowsError(
            try PeriodReportShare.activity(for: report, format: .pdf, directory: blocker)
        ) { error in
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    private func pageText(_ document: PDFDocument) -> String {
        (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    private func weekReport() -> PeriodReport {
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
        let load = PeriodReportLoadInput(
            tripId: "T-01",
            rate: 1800,
            loadedMiles: 420,
            emptyMiles: 10,
            filedOn: day,
            pickupAt: day,
            deliveryAt: day,
            weekNumber: ref.weekNumber,
            year: ref.year,
            origin: "Dallas, TX",
            destination: "Chicago, IL",
            source: .broker
        )
        return PeriodReportBuilder.build(
            PeriodReportRequest(
                driverName: "Alex Rivera",
                scope: .week(ref),
                loads: [load],
                fuel: [],
                expenses: [],
                weeklyGoal: 12_000,
                generatedAt: day,
                language: .english,
                measurementSystem: .miles,
                week: week
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("truckorig-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
}
