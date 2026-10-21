import Foundation
import Observation

/// A photo taken in the app, stored on disk and referenced by name.
///
/// Only the relative file name is persisted: the app container path changes between installs and
/// device restores, so absolute paths go stale.
@Observable
final class Photo: Identifiable {
    var id: UUID
    var fileName: String
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date
    var caption: String?
    /// Persisted foreign key. `load` is filled in when the catalog is assembled.
    var loadId: UUID?

    var load: Load? {
        didSet { loadId = load?.id }
    }

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

}
