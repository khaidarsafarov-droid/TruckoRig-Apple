import XCTest
@testable import TruckoRigDomain

final class MediaCaptureTests: XCTestCase {

    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    func testAttachmentNameUsesTripIdAndDate() {
        let name = AttachmentNaming.buildFileName(
            tripId: "114RS221Y",
            loadDate: "2026-07-21",
            timestamp: instant(2026, 7, 21, 14, 30, 52),
            extension: "jpg",
            timeZone: utc
        )
        XCTAssertEqual(name, "114RS221Y_2026-07-21_143052.jpg")
    }

    func testAttachmentNameFallsBackToTimestampDate() {
        let name = AttachmentNaming.buildFileName(
            tripId: "T-1",
            loadDate: "  ",
            timestamp: instant(2026, 7, 21, 1, 2, 3),
            extension: ".pdf",
            timeZone: utc
        )
        XCTAssertEqual(name, "T-1_2026-07-21_010203.pdf")
    }

    func testSanitizeStripsUnsafeCharacters() {
        XCTAssertEqual(AttachmentNaming.sanitize("T-116KYL6KW"), "T-116KYL6KW")
        XCTAssertEqual(AttachmentNaming.sanitize("Trip ID"), "Trip_ID")
        XCTAssertEqual(AttachmentNaming.sanitize("???"), "file")
        XCTAssertEqual(AttachmentNaming.sanitize("a/b"), "a_b")
    }

    func testFreePhotoNameIncludesStampAndMillis() {
        let timestamp = instant(2026, 7, 21, 14, 30, 52)
        let name = PhotoCapture.fileName(tripId: nil, loadDate: nil, timestamp: timestamp, timeZone: utc)
        XCTAssertEqual(name, "photo_20260721_143052_\(MediaClock.epochMillis(timestamp)).jpg")
    }

    func testScanNameWithoutTripOmitsMillis() {
        let name = ScanCapture.fileName(
            timestamp: instant(2026, 7, 21, 14, 30, 52),
            tripId: " ",
            loadDate: nil,
            timeZone: utc
        )
        XCTAssertEqual(name, "scan_20260721_143052.pdf")
    }

    func testWatermarkTitleAndMissingGPS() {
        XCTAssertEqual(PhotoCapture.resolveWatermarkTitle(watermarkTitle: "T-ABC", tripId: "T-OTHER", fallback: "TruckoRig"), "T-ABC")
        XCTAssertEqual(PhotoCapture.resolveWatermarkTitle(watermarkTitle: nil, tripId: "T-1", fallback: "TruckoRig"), "T-1")
        XCTAssertEqual(PhotoCapture.resolveWatermarkTitle(watermarkTitle: "  ", tripId: nil, fallback: "TruckoRig"), "TruckoRig")
        XCTAssertEqual(
            PhotoCapture.resolveGpsWatermarkLine(hasCoordinates: false, coordinatesLine: "1.000° N, 2.000° W", unknownLabel: "Unknown"),
            "Unknown"
        )
        XCTAssertEqual(
            PhotoCapture.resolveGpsWatermarkLine(hasCoordinates: true, coordinatesLine: "35.123° N, 78.456° W", unknownLabel: "Unknown"),
            "35.123° N, 78.456° W"
        )
    }

    func testLocationStampFormatsLikeAndroid() {
        let empty = LocationStamp()
        XCTAssertFalse(empty.hasCoordinates)
        XCTAssertEqual(empty.coordinatesLine, "—")
        XCTAssertEqual(empty.cityStateLine, "—")
        XCTAssertEqual(empty.persistedLatitude, 0)
        XCTAssertEqual(empty.persistedLongitude, 0)

        let fix = LocationStamp(latitude: 35.1234, longitude: -78.4567, city: "Garner", state: "NC", zipCode: "27529")
        XCTAssertTrue(fix.hasCoordinates)
        XCTAssertEqual(fix.coordinatesLine, "35.123° N, 78.457° W")
        XCTAssertEqual(fix.cityStateLine, "Garner, NC")
        XCTAssertEqual(PhotoMetadataDisplay.placeLine(city: fix.city, state: fix.state, zipCode: fix.zipCode), "Garner, NC 27529")
    }

    func testWatermarkLinesUseUnknownWhenPlaceIsMissing() {
        let lines = PhotoCapture.watermarkLines(
            title: nil,
            tripId: "T-9",
            timestamp: instant(2026, 7, 21, 8, 5, 0),
            location: LocationStamp(),
            unknownLabel: "Неизвестно",
            timeZone: utc,
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertEqual(lines, [
            "T-9",
            "21.07.2026 08:05",
            "—",
            "Неизвестно",
            "Неизвестно",
        ])
    }

    func testStoredPhotoFieldsMatchTheRoomColumns() {
        let timestamp = instant(2026, 7, 21, 14, 30, 52)
        let fields = StoredPhotoFields.make(
            tripId: "114RS221Y",
            loadDate: "2026-07-21",
            location: LocationStamp(latitude: nil, longitude: nil, city: "", state: "", zipCode: ""),
            timestamp: timestamp,
            loadId: "load-1",
            timeZone: utc
        )
        XCTAssertEqual(fields.fileName, "114RS221Y_2026-07-21_143052.jpg")
        XCTAssertEqual(fields.filePath, "photos/114RS221Y_2026-07-21_143052.jpg")
        XCTAssertEqual(fields.latitude, 0)
        XCTAssertEqual(fields.longitude, 0)
        XCTAssertEqual(fields.city, "")
        XCTAssertEqual(fields.state, "")
        XCTAssertEqual(fields.zipCode, "")
        XCTAssertEqual(fields.timestampMillis, MediaClock.epochMillis(timestamp))
        XCTAssertEqual(fields.loadId, "load-1")
    }

    func testSampleSizeKeepsTheLongEdge() {
        XCTAssertEqual(PhotoCapture.sampleSize(longEdge: 2048), 1)
        XCTAssertEqual(PhotoCapture.sampleSize(longEdge: 4000), 1)
        XCTAssertEqual(PhotoCapture.sampleSize(longEdge: 4096), 2)
        XCTAssertEqual(PhotoCapture.sampleSize(longEdge: 9000), 4)
        XCTAssertEqual(PhotoCapture.sampleSize(longEdge: 0), 1)
        XCTAssertEqual(PhotoCapture.sampleSize(width: 5000, height: 100), 2)
    }

    func testFlashCyclesOffAutoOn() {
        XCTAssertEqual(CameraFlashMode.off.next, .auto)
        XCTAssertEqual(CameraFlashMode.auto.next, .on)
        XCTAssertEqual(CameraFlashMode.on.next, .off)
    }

    func testCameraAttachContext() {
        XCTAssertNil(CameraAttachContext.fromExplicit(attachLoadId: nil, attachTripId: nil, attachLoadDate: "2026-07-01"))
        XCTAssertNil(CameraAttachContext.fromExplicit(attachLoadId: "  ", attachTripId: "", attachLoadDate: "2026-07-01"))
        let explicit = CameraAttachContext.fromExplicit(attachLoadId: "id-1", attachTripId: "T-1", attachLoadDate: "2026-07-21")
        XCTAssertEqual(explicit?.loadId, "id-1")
        XCTAssertEqual(explicit?.tripId, "T-1")
        XCTAssertEqual(explicit?.loadDate, "2026-07-21")
        let latest = CameraAttachContext.fromLatestLoad(loadId: "  ", tripId: "TRIP", loadDate: "")
        XCTAssertNil(latest.loadId)
        XCTAssertEqual(latest.tripId, "TRIP")
        XCTAssertNil(latest.loadDate)
        XCTAssertTrue(PhotoCapture.needsDiscardConfirmation(anySavedToDatabase: true, attachedToLoad: true))
        XCTAssertFalse(PhotoCapture.needsDiscardConfirmation(anySavedToDatabase: true, attachedToLoad: false))
    }

    func testScanCategoryInferenceAndSearch() {
        XCTAssertEqual(ScanDocumentFinder.infer(loadId: "load-1", fileName: "scan.pdf", ocrText: "diesel gallons"), .load)
        XCTAssertEqual(ScanDocumentFinder.infer(loadId: nil, fileName: "week.pdf", ocrText: "Settlement paycheck for week 34"), .paycheck)
        XCTAssertEqual(ScanDocumentFinder.infer(loadId: nil, fileName: "fuel.pdf", ocrText: "Diesel 500 gallons"), .diesel)
        XCTAssertEqual(ScanDocumentFinder.infer(loadId: nil, fileName: "cdl.pdf", ocrText: "Insurance and CDL registration"), .truck)
        XCTAssertEqual(ScanDocumentFinder.infer(loadId: nil, fileName: "note.pdf", ocrText: "hello world"), .other)
        XCTAssertEqual(ScanDocumentCategory.fromStored(nil), .other)
        XCTAssertEqual(ScanDocumentCategory.fromStored("NOPE"), .other)
        XCTAssertEqual(ScanDocumentCategory.fromStored("load"), .load)
        XCTAssertTrue(ScanDocumentFinder.matches(
            storedCategory: "PAYCHECK",
            fileName: "week.pdf",
            ocrText: "",
            tripId: "T-1",
            routeLabel: "—",
            dateLabel: "25.08.2026",
            filter: .paycheck,
            query: "зарплата"
        ))
        XCTAssertFalse(ScanDocumentFinder.matches(
            storedCategory: "PAYCHECK",
            fileName: "week.pdf",
            ocrText: "",
            tripId: "T-1",
            routeLabel: "—",
            dateLabel: "25.08.2026",
            filter: .diesel,
            query: ""
        ))
    }

    func testStoredScanFieldsAndMergedText() {
        let timestamp = instant(2026, 7, 21, 14, 30, 52)
        let fields = StoredScanFields.make(
            tripId: nil,
            loadDate: nil,
            timestamp: timestamp,
            fileSizeBytes: 2048,
            pageCount: 2,
            ocrText: "Diesel 12 gallons",
            loadId: nil,
            category: nil,
            timeZone: utc
        )
        XCTAssertEqual(fields.fileName, "scan_20260721_143052.pdf")
        XCTAssertEqual(fields.filePath, "scans/scan_20260721_143052.pdf")
        XCTAssertEqual(fields.category, ScanDocumentCategory.diesel.rawValue)
        XCTAssertEqual(fields.fileSizeBytes, 2048)
        XCTAssertEqual(fields.pageCount, 2)
        XCTAssertEqual(ScanCapture.formatFileSize(512), "512 B")
        XCTAssertEqual(ScanCapture.formatFileSize(1536), "1.5 KB")
        XCTAssertEqual(ScanCapture.formatFileSize(2 * 1024 * 1024), "2.0 MB")
        XCTAssertEqual(ScanCapture.joinPageText(["BOL", "page two"]), "BOL\n\n—\n\npage two")
        XCTAssertEqual(ScanCapture.mergedOcrText(["first", "second"]), "first\n\n---\n\nsecond")
        XCTAssertEqual(ScanCapture.cappedPageCount(25), 20)
        XCTAssertEqual(ScanListText.resolveTripId(fileName: "114RS221Y_2026-07-21_143052.pdf", loadTripId: nil), "114RS221Y")
        XCTAssertEqual(
            ScanListText.extractRoute(from: "Shipper: Garner, NC\nConsignee: Dallas, TX"),
            "Garner, NC → Dallas, TX"
        )
    }

    func testAttachPickerKeepsThisWeekAndSearchesTheJournal() {
        let older = AttachLoadCandidate(
            id: "1", tripId: "OLD", date: "2026-07-01", parsedAt: instant(2026, 7, 1, 0, 0, 0),
            pointA: "A", pointB: "B", route: "A → B", weekNumber: 26, year: 2026
        )
        let first = AttachLoadCandidate(
            id: "2", tripId: "T-NEW", date: "2026-07-21", parsedAt: instant(2026, 7, 21, 1, 0, 0),
            pointA: "Garner", pointB: "Dallas", route: "Garner → Dallas", weekNumber: 30, year: 2026
        )
        let second = AttachLoadCandidate(
            id: "3", tripId: "T-OLDER-TODAY", date: "2026-07-20", parsedAt: instant(2026, 7, 22, 1, 0, 0),
            pointA: "X", pointB: "Y", route: "X → Y", weekNumber: 30, year: 2026
        )
        let quick = AttachLoadSelection.quickPickThisWeek(loads: [older, second, first], weekNumber: 30, year: 2026)
        XCTAssertEqual(quick.map(\.id), ["2", "3"])
        let found = AttachLoadSelection.filterBrowse(loads: [older, first], query: "garner")
        XCTAssertEqual(found.map(\.id), ["2"])
        XCTAssertEqual(AttachLoadSelection.quickPickLimit, 3)
    }

    func testGalleryBoundsUseTheConfiguredWeekStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        calendar.firstWeekday = 1
        let now = instant(2026, 7, 22, 15, 30, 0)
        let start = PhotoGalleryTimeBounds.startOfDay(now, calendar: calendar)
        var parts = calendar.dateComponents([.hour, .minute, .day], from: start)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(parts.day, 22)
        let end = PhotoGalleryTimeBounds.endOfDay(now, calendar: calendar)
        parts = calendar.dateComponents([.hour, .minute, .second], from: end)
        XCTAssertEqual(parts.hour, 23)
        XCTAssertEqual(parts.minute, 59)
        XCTAssertEqual(parts.second, 59)
        XCTAssertTrue(PhotoGalleryTimeBounds.isInToday(instant(2026, 7, 22, 12, 0, 0), now: now, calendar: calendar))
        XCTAssertFalse(PhotoGalleryTimeBounds.isInToday(instant(2026, 7, 21, 23, 59, 0), now: now, calendar: calendar))
        let weekStart = PhotoGalleryTimeBounds.startOfWeek(now, calendar: calendar)
        let weekParts = calendar.dateComponents([.day], from: weekStart)
        XCTAssertEqual(weekParts.day, 19)
        XCTAssertFalse(PhotoGalleryTimeBounds.isInThisWeek(weekStart.addingTimeInterval(-1), now: now, calendar: calendar))
        XCTAssertTrue(PhotoGalleryTimeBounds.isInThisWeek(weekStart, now: now, calendar: calendar))
    }

    func testLanguageDetectorAndOrphans() {
        XCTAssertEqual(ScanLanguageDetector.detect("Привет водитель"), "ru")
        XCTAssertEqual(ScanLanguageDetector.detect("Hello driver"), "en")
        XCTAssertEqual(ScanLanguageDetector.detect("   "), "unknown")
        let orphans = OrphanScanCleanup.unreferenced(
            fileNames: ["keep.pdf", "gone.pdf"],
            knownRelativePaths: ["scans/keep.pdf"]
        )
        XCTAssertEqual(orphans, ["gone.pdf"])
    }
}
