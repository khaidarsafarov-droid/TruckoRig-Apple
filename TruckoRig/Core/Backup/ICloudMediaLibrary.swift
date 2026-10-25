import Foundation

/// Photos and scans on this phone, shaped for the iCloud manifest.
///
/// Receipts are not included. The Telegram token is never read here. Text fields are redacted
/// by `ICloudMediaPolicy` before they are written. File bytes are copied as they are, so a GPS
/// tag already in the JPEG stays in the JPEG. The row's latitude and longitude are stored in
/// the manifest because the camera watermark keeps the fix on the photo record.
enum ICloudMediaLibrary {
    struct Snapshot: Equatable {
        var items: [ICloudMediaPolicy.Item]
        var bytes: [String: Data]
    }

    struct Applied: Equatable {
        var restored: Int
        var recordIds: [String]
    }

    static func snapshot(graph: AppDatabase.StoredGraph, store: MediaStore) -> Snapshot {
        let trips = Dictionary(uniqueKeysWithValues: graph.loads.map { ($0.id, $0.tripId) })
        var items: [ICloudMediaPolicy.Item] = []
        var bytes: [String: Data] = [:]
        for photo in graph.photos {
            guard let relative = ICloudMediaPolicy.canonicalRelativePath(
                kind: ICloudMediaPolicy.Kind.photo,
                fileName: photo.fileName
            ), let data = fileData(photo.fileName, filePath: photo.filePath, kind: .photo, store: store) else { continue }
            let stamp = modifiedAt(photo.fileName, filePath: photo.filePath, kind: .photo, store: store)
            items.append(ICloudMediaPolicy.Item(
                recordId: photo.id.uuidString,
                kind: ICloudMediaPolicy.Kind.photo,
                fileName: photo.fileName,
                relativePath: relative,
                modifiedAt: stamp,
                loadId: (photo.loadId ?? photo.load?.id)?.uuidString,
                tripId: (photo.loadId ?? photo.load?.id).flatMap { trips[$0] },
                latitude: photo.latitude,
                longitude: photo.longitude,
                city: photo.city,
                state: photo.state,
                zipCode: photo.zipCode,
                timestampMillis: millis(photo.timestamp),
                caption: photo.caption
            ))
            bytes[relative] = data
        }
        for scan in graph.scans {
            guard let relative = ICloudMediaPolicy.canonicalRelativePath(
                kind: ICloudMediaPolicy.Kind.scan,
                fileName: scan.fileName
            ), let data = fileData(scan.fileName, filePath: scan.filePath, kind: .scan, store: store) else { continue }
            let stamp = modifiedAt(scan.fileName, filePath: scan.filePath, kind: .scan, store: store)
            items.append(ICloudMediaPolicy.Item(
                recordId: scan.id.uuidString,
                kind: ICloudMediaPolicy.Kind.scan,
                fileName: scan.fileName,
                relativePath: relative,
                modifiedAt: stamp,
                loadId: (scan.loadId ?? scan.load?.id)?.uuidString,
                tripId: (scan.loadId ?? scan.load?.id).flatMap { trips[$0] },
                timestampMillis: millis(scan.timestamp),
                ocrText: scan.ocrText,
                title: scan.title,
                pageCount: scan.pageCount,
                category: scan.category
            ))
            bytes[relative] = data
        }
        return Snapshot(items: items, bytes: bytes)
    }

    /// Writes bytes first, then the row. A load id that is not on this phone is left blank
    /// so the foreign key does not fail. One bad file does not stop the rest.
    static func apply(
        _ payload: ICloudMediaRestorePayload,
        to database: AppDatabase,
        media: MediaStore,
        loads: [Load]
    ) -> Applied {
        var restored = 0
        var ids: [String] = []
        for item in payload.files {
            guard let data = payload.bytes[item.relativePath] else { continue }
            let loadId = resolvedLoadId(item, loads: loads)
            do {
                if item.kind == ICloudMediaPolicy.Kind.scan {
                    try media.write(data, fileName: item.fileName, kind: .scan)
                    let scan = Scan(
                        id: stableId(item.recordId),
                        fileName: item.fileName,
                        filePath: item.relativePath,
                        ocrText: item.ocrText,
                        title: item.title,
                        timestamp: date(item.timestampMillis),
                        fileSizeBytes: Int64(data.count),
                        pageCount: item.pageCount,
                        category: item.category.isEmpty ? ScanDocumentCategory.other.rawValue : item.category
                    )
                    scan.loadId = loadId
                    try database.save(scan)
                } else {
                    try media.write(data, fileName: item.fileName, kind: .photo)
                    let photo = Photo(
                        id: stableId(item.recordId),
                        fileName: item.fileName,
                        filePath: item.relativePath,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        city: item.city,
                        state: item.state,
                        zipCode: item.zipCode,
                        timestamp: date(item.timestampMillis),
                        caption: item.caption
                    )
                    photo.loadId = loadId
                    try database.save(photo)
                }
                restored += 1
                ids.append(item.recordId)
            } catch {
                continue
            }
        }
        return Applied(restored: restored, recordIds: ids)
    }

    private static func resolvedLoadId(_ item: ICloudMediaPolicy.Item, loads: [Load]) -> UUID? {
        if let raw = item.loadId, let uuid = UUID(uuidString: raw), loads.contains(where: { $0.id == uuid }) {
            return uuid
        }
        let trip = item.tripId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trip.isEmpty {
            let matches = loads.filter { $0.tripId == trip }
            if matches.count == 1 { return matches[0].id }
        }
        return nil
    }

    private static func stableId(_ recordId: String) -> UUID {
        UUID(uuidString: recordId) ?? BackupIdentity.deterministicUUID(recordId)
    }

    private static func fileData(
        _ fileName: String,
        filePath: String?,
        kind: MediaStore.Kind,
        store: MediaStore
    ) -> Data? {
        guard let url = store.existingFile(fileName: fileName, filePath: filePath, kind: kind) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func modifiedAt(
        _ fileName: String,
        filePath: String?,
        kind: MediaStore.Kind,
        store: MediaStore
    ) -> Int64 {
        guard let url = store.existingFile(fileName: fileName, filePath: filePath, kind: kind),
              let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return 0 }
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(_ millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }
}
