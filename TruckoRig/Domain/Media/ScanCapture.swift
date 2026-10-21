import Foundation

/// Driver-facing folders for scanned papers. Stored as the enum name on the scans table.
public enum ScanDocumentCategory: String, Equatable, Sendable, CaseIterable {
    case load = "LOAD"
    case paycheck = "PAYCHECK"
    case diesel = "DIESEL"
    case truck = "TRUCK"
    case other = "OTHER"

    public static func fromStored(_ value: String?) -> ScanDocumentCategory {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return allCases.first { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame } ?? .other
    }
}

/// Port of Android `ScanDocumentFinder`.
public enum ScanDocumentFinder {
    public static func infer(loadId: String?, fileName: String, ocrText: String) -> ScanDocumentCategory {
        if let loadId, !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .load
        }
        let hay = "\(fileName)\n\(ocrText)".lowercased()
        let scored = preferOrder.map { category in
            (category, keywords[category, default: []].filter { hay.contains($0) }.count)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return .other }
        let tied = Set(scored.filter { $0.1 == best.1 }.map(\.0))
        return preferOrder.first { tied.contains($0) } ?? .other
    }

    public static func matches(
        storedCategory: String,
        fileName: String,
        ocrText: String,
        tripId: String,
        routeLabel: String,
        dateLabel: String,
        filter: ScanDocumentCategory?,
        query: String
    ) -> Bool {
        let category = ScanDocumentCategory.fromStored(storedCategory)
        if let filter, category != filter { return false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return true }
        var hay = [fileName, ocrText, tripId, routeLabel, dateLabel, category.rawValue]
        hay.append(contentsOf: searchAliases[category] ?? [])
        return hay.joined(separator: "\n").lowercased().contains(needle)
    }

    private static let preferOrder: [ScanDocumentCategory] = [.load, .paycheck, .diesel, .truck]

    private static let keywords: [ScanDocumentCategory: [String]] = [
        .load: [
            "bill of lading", "rate confirmation", "rate con", "ratecon", "trip id",
            "load confirmation", "bol", "накладн", "груз", "relay", "consignee", "shipper", "pickup",
        ],
        .paycheck: [
            "paycheck", "pay check", "settlement", "payroll", "statement of earnings",
            "зарплат", "выплат", "расчётн", "расчетн",
        ],
        .diesel: ["diesel", "fuel receipt", "fuel stop", "gallons", "gallon", "дизел", "топлив", "галлон"],
        .truck: [
            "insurance", "registration", "inspection", "ifta", "irp", "cdl", "title",
            "страхов", "регистрац", "техосмотр", "допуск", "медкниж",
        ],
    ]

    private static let searchAliases: [ScanDocumentCategory: [String]] = [
        .load: ["груз", "load", "bol"],
        .paycheck: ["зарплата", "paycheck", "settlement"],
        .diesel: ["дизель", "diesel", "fuel"],
        .truck: ["машина", "truck", "insurance", "cdl"],
        .other: ["другое", "other"],
    ]
}

/// PDF naming, page cap, file size and merged OCR text. Port of `PDFGenerator` and `ScannerViewModel`.
public enum ScanCapture {
    public static let directoryName = "scans"
    public static let pageLimit = 20

    public static func fileName(
        timestamp: Date = Date(),
        tripId: String? = nil,
        loadDate: String? = nil,
        timeZone: TimeZone = .current
    ) -> String {
        if let tripId, !tripId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttachmentNaming.buildFileName(
                tripId: tripId,
                loadDate: loadDate ?? "",
                timestamp: timestamp,
                extension: "pdf",
                timeZone: timeZone
            )
        }
        let stamp = MediaClock.format(timestamp, pattern: "yyyyMMdd_HHmmss", timeZone: timeZone)
        return "scan_\(stamp).pdf"
    }

    public static func relativePath(fileName: String) -> String {
        "\(directoryName)/\(fileName)"
    }

    public static func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kilobytes = Double(bytes) / 1024
        if kilobytes < 1024 {
            return String(format: "%.1f KB", locale: Locale(identifier: "en_US_POSIX"), kilobytes)
        }
        let megabytes = kilobytes / 1024
        return String(format: "%.1f MB", locale: Locale(identifier: "en_US_POSIX"), megabytes)
    }

    /// One scan's pages joined the way `OCRService.recognizeScanResult` joins them.
    public static func joinPageText(_ pages: [String]) -> String {
        pages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n—\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Several scans in one session become one PDF. Port of `buildMergedPending`.
    public static func mergedOcrText(_ parts: [String]) -> String {
        parts.enumerated().map { index, text in
            index == 0 ? text : "---\n\n\(text)"
        }.joined(separator: "\n\n")
    }

    public static func cappedPageCount(_ count: Int) -> Int {
        min(max(count, 0), pageLimit)
    }
}

/// Columns written to the scan table. Cloud-sync columns from Room are omitted.
public struct StoredScanFields: Equatable, Sendable {
    public var fileName: String
    public var filePath: String
    public var timestampMillis: Int64
    public var fileSizeBytes: Int64
    public var pageCount: Int
    public var ocrText: String
    public var loadId: String?
    public var category: String

    public init(
        fileName: String,
        filePath: String,
        timestampMillis: Int64,
        fileSizeBytes: Int64,
        pageCount: Int,
        ocrText: String,
        loadId: String?,
        category: String
    ) {
        self.fileName = fileName
        self.filePath = filePath
        self.timestampMillis = timestampMillis
        self.fileSizeBytes = fileSizeBytes
        self.pageCount = pageCount
        self.ocrText = ocrText
        self.loadId = loadId
        self.category = category
    }

    public static func make(
        tripId: String?,
        loadDate: String?,
        timestamp: Date,
        fileSizeBytes: Int64,
        pageCount: Int,
        ocrText: String,
        loadId: String?,
        category: ScanDocumentCategory? = nil,
        timeZone: TimeZone = .current
    ) -> StoredScanFields {
        let name = ScanCapture.fileName(
            timestamp: timestamp,
            tripId: tripId,
            loadDate: loadDate,
            timeZone: timeZone
        )
        let resolved = category ?? ScanDocumentFinder.infer(loadId: loadId, fileName: name, ocrText: ocrText)
        return StoredScanFields(
            fileName: name,
            filePath: ScanCapture.relativePath(fileName: name),
            timestampMillis: MediaClock.epochMillis(timestamp),
            fileSizeBytes: fileSizeBytes,
            pageCount: pageCount,
            ocrText: ocrText,
            loadId: loadId,
            category: resolved.rawValue
        )
    }
}

public enum ScanListText {
    public static func resolveTripId(fileName: String, loadTripId: String?) -> String {
        if let loadTripId, !loadTripId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return loadTripId
        }
        let fromName = fileName.split(separator: "_").first.map(String.init) ?? fileName
        let beforeDot = fromName.split(separator: ".").first.map(String.init) ?? fromName
        if !beforeDot.isEmpty && beforeDot != fileName { return beforeDot }
        return fileName
    }

    public static func extractRoute(from ocr: String) -> String? {
        let trimmed = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let lines = trimmed.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        let shipper = value(after: "Shipper:", in: lines)
        let consignee = value(afterAny: ["Consignee:", "Receiver:", "Delivery:"], in: lines)
        if let shipper, let consignee, !shipper.isEmpty, !consignee.isEmpty {
            return "\(shipper) → \(consignee)"
        }
        if let shipper, !shipper.isEmpty { return shipper }
        return nil
    }

    public static func dateLabel(timestamp: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        MediaClock.format(timestamp, pattern: "dd.MM.yyyy", timeZone: timeZone, locale: locale)
    }

    private static func value(after prefix: String, in lines: [String]) -> String? {
        value(afterAny: [prefix], in: lines)
    }

    private static func value(afterAny prefixes: [String], in lines: [String]) -> String? {
        for line in lines {
            for prefix in prefixes where line.lowercased().hasPrefix(prefix.lowercased()) {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return value
            }
        }
        return nil
    }
}

/// `ru` / `en` / `mixed` / `unknown`, matching Android `LanguageDetector`.
public enum ScanLanguageDetector {
    public static func detect(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "unknown" }
        let cyrillic = text.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }.count
        let latin = text.filter { ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z") }.count
        let letters = cyrillic + latin
        if letters == 0 { return "unknown" }
        if Double(cyrillic) / Double(letters) >= 0.3 { return "ru" }
        if Double(latin) / Double(letters) >= 0.5 { return "en" }
        return "mixed"
    }
}

/// Files under `scans/` that no row points at.
public enum OrphanScanCleanup {
    public static func unreferenced(fileNames: [String], knownRelativePaths: Set<String>) -> [String] {
        let knownNames = Set(knownRelativePaths.map { path in
            path.split(separator: "/").last.map(String.init) ?? path
        })
        return fileNames.filter { name in
            let relative = ScanCapture.relativePath(fileName: name)
            return !knownRelativePaths.contains(relative)
                && !knownNames.contains(name)
                && !knownRelativePaths.contains(name)
        }
    }
}
