import Foundation
import GRDB

/// Photo and scan rows.
extension AppDatabase {
    static func fetchPhotoRows(_ db: Database) throws -> [Photo] {
        try Row.fetchAll(db, sql: "SELECT * FROM photo ORDER BY timestamp DESC").map(photo(from:))
    }


    static func fetchScanRows(_ db: Database) throws -> [Scan] {
        try Row.fetchAll(db, sql: "SELECT * FROM scan ORDER BY timestamp DESC").map(scan(from:))
    }


    static func attach(_ photos: [Photo], to loads: [Load]) {
        let loadsById = Dictionary(uniqueKeysWithValues: loads.map { ($0.id, $0) })
        for photo in photos {
            guard let loadId = photo.loadId, let load = loadsById[loadId] else { continue }
            photo.load = load
            load.photos = (load.photos ?? []) + [photo]
        }
    }


    static func attach(_ scans: [Scan], to loads: [Load]) {
        let loadsById = Dictionary(uniqueKeysWithValues: loads.map { ($0.id, $0) })
        for scan in scans {
            guard let loadId = scan.loadId, let load = loadsById[loadId] else { continue }
            scan.load = load
            load.scans = (load.scans ?? []) + [scan]
        }
    }


    static func upsert(_ db: Database, _ photo: Photo) throws {
        try execute(db, """
        INSERT INTO photo (
            id, loadId, fileName, filePath, latitude, longitude, city, state, zipCode, timestamp, caption
        ) VALUES (\(marks(11)))
        ON CONFLICT(id) DO UPDATE SET
            loadId = excluded.loadId, fileName = excluded.fileName, filePath = excluded.filePath,
            latitude = excluded.latitude, longitude = excluded.longitude,
            city = excluded.city, state = excluded.state, zipCode = excluded.zipCode,
            timestamp = excluded.timestamp, caption = excluded.caption
        """, [
            photo.id.uuidString, (photo.loadId ?? photo.load?.id)?.uuidString, photo.fileName, photo.filePath,
            photo.latitude, photo.longitude, photo.city, photo.state, photo.zipCode,
            photo.timestamp.timeIntervalSince1970, photo.caption,
        ])
    }


    static func upsert(_ db: Database, _ scan: Scan) throws {
        try execute(db, """
        INSERT INTO scan (
            id, loadId, fileName, filePath, ocrText, title, timestamp, fileSizeBytes, pageCount, category
        ) VALUES (\(marks(10)))
        ON CONFLICT(id) DO UPDATE SET
            loadId = excluded.loadId, fileName = excluded.fileName, filePath = excluded.filePath,
            ocrText = excluded.ocrText, title = excluded.title, timestamp = excluded.timestamp,
            fileSizeBytes = excluded.fileSizeBytes, pageCount = excluded.pageCount,
            category = excluded.category
        """, [
            scan.id.uuidString, (scan.loadId ?? scan.load?.id)?.uuidString, scan.fileName, scan.filePath,
            scan.ocrText, scan.title, scan.timestamp.timeIntervalSince1970, scan.fileSizeBytes,
            scan.pageCount, scan.category,
        ])
    }


    static func photo(from row: Row) -> Photo {
        let photo = Photo(
            id: uuid(row, "id") ?? UUID(),
            fileName: string(row, "fileName") ?? "",
            filePath: string(row, "filePath"),
            latitude: double(row, "latitude"),
            longitude: double(row, "longitude"),
            city: string(row, "city") ?? "",
            state: string(row, "state") ?? "",
            zipCode: string(row, "zipCode") ?? "",
            timestamp: date(row, "timestamp") ?? Date(timeIntervalSince1970: 0),
            caption: string(row, "caption")
        )
        photo.loadId = uuid(row, "loadId")
        return photo
    }


    static func scan(from row: Row) -> Scan {
        let scan = Scan(
            id: uuid(row, "id") ?? UUID(),
            fileName: string(row, "fileName") ?? "",
            filePath: string(row, "filePath"),
            ocrText: string(row, "ocrText"),
            title: string(row, "title"),
            timestamp: date(row, "timestamp") ?? Date(timeIntervalSince1970: 0),
            fileSizeBytes: int64(row, "fileSizeBytes") ?? 0,
            pageCount: int(row, "pageCount") ?? 1,
            category: string(row, "category") ?? ScanDocumentCategory.other.rawValue
        )
        scan.loadId = uuid(row, "loadId")
        return scan
    }
}
