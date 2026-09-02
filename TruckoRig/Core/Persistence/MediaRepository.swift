import Foundation
import SwiftData
import UIKit

/// Writes for photos and scans: file first, then the row.
@MainActor
struct MediaRepository {

    let context: ModelContext
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
        try context.save()
        return scan
    }

    func attach(_ photo: Photo, to load: Load?) throws {
        photo.load = load
        try context.save()
    }

    func attach(_ scan: Scan, to load: Load?) throws {
        scan.load = load
        try context.save()
    }

    func delete(_ photo: Photo) throws {
        store.delete(fileName: photo.fileName, kind: .photo)
        context.delete(photo)
        try context.save()
    }

    func delete(_ scan: Scan) throws {
        store.delete(fileName: scan.fileName, kind: .scan)
        context.delete(scan)
        try context.save()
    }
}
