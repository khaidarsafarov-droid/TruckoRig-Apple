import Foundation
import Observation

/// A scanned document. Fields match Android `ScanEntity` except the cloud-sync columns.
///
/// The file is a PDF under `scans/`. `title` remains for rows saved before categories existed.
@Observable
final class Scan: Identifiable {
    var id: UUID
    var fileName: String
    var filePath: String?
    /// Text recognised by Vision. Never logged — scans routinely contain personal data.
    var ocrText: String?
    var title: String?
    var timestamp: Date
    var fileSizeBytes: Int64
    var pageCount: Int
    var category: String
    /// Persisted foreign key. `load` is filled in when the catalog is assembled.
    var loadId: UUID?

    var load: Load? {
        didSet { loadId = load?.id }
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String? = nil,
        ocrText: String? = nil,
        title: String? = nil,
        timestamp: Date = Date(),
        fileSizeBytes: Int64 = 0,
        pageCount: Int = 1,
        category: String = ScanDocumentCategory.other.rawValue
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.ocrText = ocrText
        self.title = title
        self.timestamp = timestamp
        self.fileSizeBytes = fileSizeBytes
        self.pageCount = pageCount
        self.category = category
    }

    var documentCategory: ScanDocumentCategory {
        get { ScanDocumentCategory.fromStored(category) }
        set { category = newValue.rawValue }
    }
}
