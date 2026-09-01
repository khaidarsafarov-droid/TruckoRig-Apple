import Foundation
import SwiftData

/// A photo taken in the app, stored on disk and referenced by name.
///
/// Only the relative file name is persisted: the app container path changes between installs and
/// device restores, so absolute paths go stale.
@Model
final class Photo {
    @Attribute(.unique) var id: UUID
    var fileName: String
    /// Object key in cloud storage once uploaded.
    var cloudPath: String?
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date
    var isUploaded: Bool
    var caption: String?

    var load: Load?

    init(
        id: UUID = UUID(),
        fileName: String,
        cloudPath: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timestamp: Date = Date(),
        isUploaded: Bool = false,
        caption: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.cloudPath = cloudPath
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.isUploaded = isUploaded
        self.caption = caption
    }

    var loadId: UUID? { load?.id }
}
