import Foundation
import SwiftData

/// A scanned document (BOL, rate confirmation, receipt) with its recognised text.
@Model
final class Scan {
    @Attribute(.unique) var id: UUID
    var fileName: String
    /// Text recognised by Vision. Never logged — scans routinely contain personal data.
    var ocrText: String?
    var title: String?
    var timestamp: Date

    var load: Load?

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

    var loadId: UUID? { load?.id }
}
