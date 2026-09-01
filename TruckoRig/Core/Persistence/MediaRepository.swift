import Foundation
import SwiftData
import UIKit

/// Writes for photos and scans: file first, then the row, then the outbox.
@MainActor
struct MediaRepository {

    let context: ModelContext
    let sync: SyncEngine
    let store: MediaStore

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
        context.insert(photo)
        sync.enqueue(.photo, id: photo.id, operation: .create, in: context)
        try context.save()
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
        context.insert(scan)
        sync.enqueue(.scan, id: scan.id, operation: .create, in: context)
        try context.save()
        return scan
    }

    func attach(_ photo: Photo, to load: Load?) throws {
        photo.load = load
        sync.enqueue(.photo, id: photo.id, operation: .update, in: context)
        try context.save()
    }

    func attach(_ scan: Scan, to load: Load?) throws {
        scan.load = load
        sync.enqueue(.scan, id: scan.id, operation: .update, in: context)
        try context.save()
    }

    func delete(_ photo: Photo) throws {
        let id = photo.id
        store.delete(fileName: photo.fileName, kind: .photo)
        context.delete(photo)
        sync.enqueue(.photo, id: id, operation: .delete, in: context)
        try context.save()
    }

    func delete(_ scan: Scan) throws {
        let id = scan.id
        store.delete(fileName: scan.fileName, kind: .scan)
        context.delete(scan)
        sync.enqueue(.scan, id: id, operation: .delete, in: context)
        try context.save()
    }
}
