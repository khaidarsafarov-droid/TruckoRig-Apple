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
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date
    var caption: String?

    var load: Load?

    init(
        id: UUID = UUID(),
        fileName: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timestamp: Date = Date(),
        caption: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.caption = caption
    }

    var loadId: UUID? { load?.id }
}
