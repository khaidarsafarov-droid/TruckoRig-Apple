import Foundation
import Observation

/// A scanned document (BOL, rate confirmation, receipt) with its recognised text.
@Observable
final class Scan: Identifiable {
    var id: UUID
    var fileName: String
    /// Text recognised by Vision. Never logged — scans routinely contain personal data.
    var ocrText: String?
    var title: String?
    var timestamp: Date
    /// Persisted foreign key. `load` is filled in when the catalog is assembled.
    var loadId: UUID?

    var load: Load? {
        didSet { loadId = load?.id }
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        ocrText: String? = nil,
        title: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.ocrText = ocrText
        self.title = title
        self.timestamp = timestamp
    }

}
