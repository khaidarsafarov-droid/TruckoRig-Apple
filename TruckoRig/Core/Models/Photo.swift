import Foundation
import Observation

/// A photo taken in the app. Fields match Android `PhotoEntity` except the cloud-sync columns.
///
/// `filePath` is relative (`photos/name.jpg`). The iOS container path changes between installs,
/// so an absolute path would go stale the way Android's external-files path does not.
@Observable
final class Photo: Identifiable {
    var id: UUID
    var fileName: String
    var filePath: String?
    var latitude: Double?
    var longitude: Double?
    var city: String
    var state: String
    var zipCode: String
    var timestamp: Date
    /// Kept so rows written before the Android field set still open. New photos leave it empty.
    var caption: String?
    /// Persisted foreign key. `load` is filled in when the catalog is assembled.
    var loadId: UUID?

    var load: Load? {
        didSet { loadId = load?.id }
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String = "",
        state: String = "",
        zipCode: String = "",
        timestamp: Date = Date(),
        caption: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.timestamp = timestamp
        self.caption = caption
    }

    var placeLine: String {
        PhotoMetadataDisplay.placeLine(city: city, state: state, zipCode: zipCode)
    }
}
