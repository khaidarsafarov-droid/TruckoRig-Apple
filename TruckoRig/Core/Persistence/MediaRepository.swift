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
    func savePhoto(
        _ image: UIImage,
        attachedTo load: Load?,
        latitude: Double?,
        longitude: Double?,
        caption: String? = nil
    ) throws -> Photo {
        let fileName = try store.save(image, kind: .photo)
        let photo = Photo(
            fileName: fileName,
            latitude: latitude,
            longitude: longitude,
            caption: caption
        )
        photo.load = load
        try database.save(photo)
        onDidSave?()
        return photo
    }

    @discardableResult
    func saveScan(
        _ image: UIImage,
        attachedTo load: Load?,
        ocrText: String?,
        title: String?
    ) throws -> Scan {
        let fileName = try store.save(image, kind: .scan)
        let scan = Scan(fileName: fileName, ocrText: ocrText, title: title)
        scan.load = load
        try database.save(scan)
        onDidSave?()
        return scan
    }

    func attach(_ photo: Photo, to load: Load?) throws {
        photo.load = load
        try database.save(photo)
        onDidSave?()
    }

    func attach(_ scan: Scan, to load: Load?) throws {
        scan.load = load
        try database.save(scan)
        onDidSave?()
    }

    func delete(_ photo: Photo) throws {
        store.delete(fileName: photo.fileName, kind: .photo)
        try database.delete(photo)
        onDidSave?()
    }

    func delete(_ scan: Scan) throws {
        store.delete(fileName: scan.fileName, kind: .scan)
        try database.delete(scan)
        onDidSave?()
    }
}
