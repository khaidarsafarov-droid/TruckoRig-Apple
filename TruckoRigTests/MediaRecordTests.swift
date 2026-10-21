import XCTest
@testable import TruckoRig

/// Photo and scan rows store the same fields Android writes, and deleting a load removes both
/// the rows and the files.
@MainActor
final class MediaRecordTests: XCTestCase {

    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
        super.tearDown()
    }

    func testPhotoAndScanRowsRoundTrip() throws {
        let database = try AppDatabase.ephemeral()
        let root = try temporaryDirectory()
        let store = MediaStore(scope: .local, root: root)
        let repository = MediaRepository(database: database, store: store, onDidSave: nil)
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let timestamp = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 14, minute: 30, second: 52))!
        let location = LocationStamp(latitude: 35.123, longitude: -78.456, city: "Garner", state: "NC", zipCode: "27529")
        let photoFields = StoredPhotoFields.make(
            tripId: "114RS221Y",
            loadDate: "2026-07-21",
            location: location,
            timestamp: timestamp,
            loadId: nil,
            timeZone: zone
        )
        let photo = try repository.savePhoto(fields: photoFields, jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), load: nil)
        let scanFields = StoredScanFields.make(
            tripId: "114RS221Y",
            loadDate: "2026-07-21",
            timestamp: timestamp,
            fileSizeBytes: 12,
            pageCount: 3,
            ocrText: "Bill of lading",
            loadId: nil,
            category: .load,
            timeZone: zone
        )
        let scan = try repository.saveScan(fields: scanFields, pdf: Data("%PDF-1.1".utf8), load: nil)

        let graph = try database.fetchGraph()
        let storedPhoto = try XCTUnwrap(graph.photos.first { $0.id == photo.id })
        XCTAssertEqual(storedPhoto.fileName, "114RS221Y_2026-07-21_143052.jpg")
        XCTAssertEqual(storedPhoto.filePath, "photos/114RS221Y_2026-07-21_143052.jpg")
        XCTAssertEqual(storedPhoto.latitude ?? -1, 35.123, accuracy: 0.0001)
        XCTAssertEqual(storedPhoto.longitude ?? 0, -78.456, accuracy: 0.0001)
        XCTAssertEqual(storedPhoto.city, "Garner")
        XCTAssertEqual(storedPhoto.state, "NC")
        XCTAssertEqual(storedPhoto.zipCode, "27529")
        XCTAssertEqual(storedPhoto.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(storedPhoto.loadId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: storedPhoto.fileName, kind: .photo).path))

        let storedScan = try XCTUnwrap(graph.scans.first { $0.id == scan.id })
        XCTAssertEqual(storedScan.fileName, "114RS221Y_2026-07-21_143052.pdf")
        XCTAssertEqual(storedScan.filePath, "scans/114RS221Y_2026-07-21_143052.pdf")
        XCTAssertEqual(storedScan.pageCount, 3)
        XCTAssertEqual(storedScan.fileSizeBytes, 12)
        XCTAssertEqual(storedScan.ocrText, "Bill of lading")
        XCTAssertEqual(storedScan.category, "LOAD")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: storedScan.fileName, kind: .scan).path))
    }

    func testDeletingALoadRemovesPhotoAndScanFiles() throws {
        let database = try AppDatabase.ephemeral()
        let root = try temporaryDirectory()
        let store = MediaStore(scope: .local, root: root)
        let repository = MediaRepository(database: database, store: store, onDidSave: nil)
        let date = Date(timeIntervalSince1970: 1_784_000_000)
        let load = Load(tripId: "T-MEDIA1", date: date, totalRate: 1000, totalMiles: 100, weekNumber: 30, year: 2026, parsedAt: date, updatedAt: date)
        try database.save(load)
        let photoFields = StoredPhotoFields.make(
            tripId: load.tripId,
            loadDate: "2026-07-21",
            location: LocationStamp(latitude: 1, longitude: 2, city: "A", state: "TX", zipCode: "75001"),
            timestamp: date,
            loadId: load.id.uuidString
        )
        let photo = try repository.savePhoto(fields: photoFields, jpeg: Data([0xFF, 0xD8]), load: load)
        let scanFields = StoredScanFields(
            fileName: "scan.pdf",
            filePath: "scans/scan.pdf",
            timestampMillis: MediaClock.epochMillis(date),
            fileSizeBytes: 4,
            pageCount: 1,
            ocrText: "rate confirmation",
            loadId: load.id.uuidString,
            category: ScanDocumentCategory.load.rawValue
        )
        let scan = try repository.saveScan(fields: scanFields, pdf: Data("%PDF".utf8), load: load)
        let photoURL = store.url(for: photo.fileName, kind: .photo)
        let scanURL = store.url(for: scan.fileName, kind: .scan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scanURL.path))

        let loads = LoadRepository(database: database)
        try loads.delete(load, mediaStore: store)

        let graph = try database.fetchGraph()
        XCTAssertTrue(graph.loads.isEmpty)
        XCTAssertTrue(graph.photos.isEmpty)
        XCTAssertTrue(graph.scans.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scanURL.path))
    }

    func testMissingGPSIsStoredAsZero() throws {
        let database = try AppDatabase.ephemeral()
        let store = MediaStore(scope: .local, root: try temporaryDirectory())
        let repository = MediaRepository(database: database, store: store, onDidSave: nil)
        let fields = StoredPhotoFields.make(
            tripId: nil,
            loadDate: nil,
            location: LocationStamp(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            loadId: nil,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let photo = try repository.savePhoto(fields: fields, jpeg: Data([1, 2, 3]), load: nil)
        let stored = try XCTUnwrap(try database.fetchGraph().photos.first { $0.id == photo.id })
        XCTAssertEqual(stored.latitude ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(stored.longitude ?? -1, 0, accuracy: 0.001)
        XCTAssertTrue(stored.fileName.hasPrefix("photo_"))
        XCTAssertEqual(stored.filePath, "photos/\(stored.fileName)")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("truckorig-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
}
