import Foundation
import UIKit

/// Writes for photos and scans: file first, then the encrypted row.
@MainActor
struct MediaRepository {

    let database: AppDatabase
    let store: MediaStore
    let onDidSave: (() -> Void)?

    init(database: AppDatabase, store: MediaStore, onDidSave: (() -> Void)? = nil) {
        self.database = database
        self.store = store
        self.onDidSave = onDidSave
    }

    @discardableResult
    func savePhoto(fields: StoredPhotoFields, jpeg: Data, load: Load?) throws -> Photo {
        _ = try store.write(jpeg, fileName: fields.fileName, kind: .photo)
        let photo = Photo(
            fileName: fields.fileName,
            filePath: fields.filePath,
            latitude: fields.latitude,
            longitude: fields.longitude,
            city: fields.city,
            state: fields.state,
            zipCode: fields.zipCode,
            timestamp: MediaClock.date(fromEpochMillis: fields.timestampMillis)
        )
        if let load {
            photo.load = load
        } else if let loadId = fields.loadId {
            photo.loadId = UUID(uuidString: loadId)
        }
        try database.save(photo)
        onDidSave?()
        return photo
    }

    @discardableResult
    func saveScan(fields: StoredScanFields, pdf: Data, load: Load?) throws -> Scan {
        _ = try store.write(pdf, fileName: fields.fileName, kind: .scan)
        let scan = Scan(
            fileName: fields.fileName,
            filePath: fields.filePath,
            ocrText: fields.ocrText,
            timestamp: MediaClock.date(fromEpochMillis: fields.timestampMillis),
            fileSizeBytes: fields.fileSizeBytes,
            pageCount: fields.pageCount,
            category: fields.category
        )
        if let load {
            scan.load = load
        } else if let loadId = fields.loadId {
            scan.loadId = UUID(uuidString: loadId)
        }
        try database.save(scan)
        onDidSave?()
        return scan
    }

    func attach(_ photo: Photo, to load: Load?) throws {
        photo.load = load
        if load == nil { photo.loadId = nil }
        try database.save(photo)
        onDidSave?()
    }

    /// Linking a scan to a load files it as `LOAD`, matching `ScanRepository.linkScanToLoad`.
    func attach(_ scan: Scan, to load: Load?) throws {
        scan.load = load
        if load == nil {
            scan.loadId = nil
        } else {
            scan.documentCategory = .load
        }
        try database.save(scan)
        onDidSave?()
    }

    func updateCategory(_ scan: Scan, category: ScanDocumentCategory) throws {
        scan.documentCategory = category
        try database.save(scan)
        onDidSave?()
    }

    func delete(_ photo: Photo) throws {
        store.delete(fileName: photo.fileName, filePath: photo.filePath, kind: .photo)
        try database.delete(photo)
        onDidSave?()
    }

    func delete(_ scan: Scan) throws {
        store.delete(fileName: scan.fileName, filePath: scan.filePath, kind: .scan)
        try database.delete(scan)
        onDidSave?()
    }

    func deleteFiles(_ media: AppDatabase.RemovedMedia) {
        for photo in media.photos {
            store.delete(fileName: photo.fileName, filePath: photo.filePath, kind: .photo)
        }
        for scan in media.scans {
            store.delete(fileName: scan.fileName, filePath: scan.filePath, kind: .scan)
        }
    }

    func cleanupOrphanScans(known: [Scan]) -> Int {
        let paths = Set(known.compactMap(\.filePath).filter { !$0.isEmpty })
        let names = Set(known.map(\.fileName))
        return store.cleanupOrphanScans(knownRelativePaths: paths.union(names))
    }
}
