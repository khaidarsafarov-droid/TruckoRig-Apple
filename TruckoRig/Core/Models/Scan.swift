import Foundation
import SwiftData

/// A scanned document (BOL, rate confirmation, receipt) with its recognised text.
@Model
final class Scan {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var cloudPath: String?
    /// Text recognised by Vision. Never logged — scans routinely contain personal data.
    var ocrText: String?
    var title: String?
    var timestamp: Date
    var isUploaded: Bool

    var load: Load?

    init(
        id: UUID = UUID(),
        fileName: String,
        cloudPath: String? = nil,
        ocrText: String? = nil,
        title: String? = nil,
        timestamp: Date = Date(),
        isUploaded: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.cloudPath = cloudPath
        self.ocrText = ocrText
        self.title = title
        self.timestamp = timestamp
        self.isUploaded = isUploaded
    }

    var loadId: UUID? { load?.id }
}
